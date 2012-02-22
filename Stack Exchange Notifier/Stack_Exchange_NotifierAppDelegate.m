//
//  Stack_Exchange_NotifierAppDelegate.m
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "Stack_Exchange_NotifierAppDelegate.h"
#include "SBJson.h"
#include "NSString+html.h"

NSString *CLIENT_KEY = @"JBpdN2wRVnHTq9E*uuyTPQ((";
NSString *DEFAULTS_KEY_READ_ITEMS = @"com.hewgill.senotifier.readitems";

NSString *timeAgo(time_t t);
void setMenuItemTitle(NSMenuItem *menuitem, NSDictionary *msg, bool highlight);

NSString *timeAgo(time_t t)
{
    long minutesago = (time(NULL) - t) / 60;
    NSString *ago;
    if (minutesago == 1) {
        ago = @" - checked 1 minute ago";
    } else if (minutesago < 60) {
        ago = [NSString stringWithFormat:@" - checked %ld minutes ago", minutesago];
    } else if (minutesago < 60*2) {
        ago = @" - checked 1 hour ago";
    } else {
        ago = [NSString stringWithFormat:@" - checked %ld hours ago", minutesago / 60];
    }
    return ago;
}

@interface IndirectTarget: NSObject {
    id _originalTarget;
    SEL _action;
    id _arg;
};

@end

@implementation IndirectTarget

-(IndirectTarget *)initWithArg:(id)arg action:(SEL)action originalTarget:(id)originalTarget
{
    _originalTarget = originalTarget;
    _action = action;
    _arg = arg;
    return self;
}

-(void)fire
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_originalTarget performSelector:_action withObject:_arg];
#pragma clang diagnostic pop
}

@end

void setMenuItemTitle(NSMenuItem *menuitem, NSDictionary *msg, bool highlight)
{
    NSFont *font = highlight ? [NSFont menuBarFontOfSize:0.0] : [NSFont menuBarFontOfSize:0.0];
    NSDictionary *attrs = [[NSDictionary alloc] initWithObjectsAndKeys:
        font, NSFontAttributeName,
        [NSNumber numberWithFloat:(highlight ? -4.0 : 0.0)], NSStrokeWidthAttributeName,
        nil];
    NSAttributedString *at = [[NSAttributedString alloc] initWithString:[[msg objectForKey:@"body"] stringByDecodingXMLEntities] attributes:attrs];
    [menuitem setAttributedTitle:at];
}

@implementation Stack_Exchange_NotifierAppDelegate

@synthesize window;

-(void)updateMenu
{
    NSDictionary *normalattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
        nil];
    NSMutableAttributedString *at = [[NSMutableAttributedString alloc] initWithString:@"Check Now" attributes:normalattrs];
    if (lastCheck) {
        NSDictionary *grayattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
            [NSColor grayColor], NSForegroundColorAttributeName,
            nil];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:timeAgo(lastCheck) attributes:grayattrs]];
    }
    [[menu itemAtIndex:2] setAttributedTitle:at];
}

-(void)resetMenu
{
    menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"About" action:@selector(showAbout) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Log in" action:@selector(doLogin) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Check Now" action:@selector(checkInbox) keyEquivalent:@""]];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    unsigned int unread = 0;
    targets = [NSMutableArray arrayWithCapacity:[items count]];
    if ([items count] > 0) {
        unsigned int i = 0;
        for (NSDictionary *obj in [items objectEnumerator]) {
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:[[obj objectForKey:@"body"] stringByDecodingXMLEntities] action:@selector(fire) keyEquivalent:@""];
            bool read = [readItems containsObject:[obj objectForKey:@"link"]];
            setMenuItemTitle(it, obj, !read);
            if (!read) {
                unread++;
            }
            IndirectTarget *t = [[IndirectTarget alloc] initWithArg:[NSNumber numberWithUnsignedInt:i] action:@selector(openUrlFromItem:) originalTarget:self];
            [targets addObject:t];
            [it setTarget:t];
            [menu addItem:it];
            i++;
        }
    } else {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"no messages" action:NULL keyEquivalent:@""]];
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Invalidate" action:@selector(invalidate) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit) keyEquivalent:@""]];

    [self updateMenu];
    
    if (unread > 0) {
        [item setTitle:[NSString stringWithFormat:@"%u", unread]];
    } else {
        [item setTitle:nil];
    }
    [item setMenu:menu];
}

-(void)doLogin
{
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    [[web mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://stackexchange.com/oauth/dialog?client_id=81&scope=read_inbox&redirect_uri=https://stackexchange.com/oauth/login_success"]]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    lastCheck = 0;
    readItems = [[NSUserDefaults standardUserDefaults] arrayForKey:DEFAULTS_KEY_READ_ITEMS];

    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    item = [bar statusItemWithLength:NSVariableStatusItemLength];
    [item setImage:[[NSImage alloc] initByReferencingFile:[[NSBundle mainBundle] pathForResource:@"favicon.ico" ofType:nil]]];
    [item setHighlightMode:YES];
    [self resetMenu];

    web = [[WebView alloc] initWithFrame:[window frame]];
    [window setContentView:web];
    [web setFrameLoadDelegate:self];

    [self doLogin];

    menuUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(updateMenu) userInfo:nil repeats:YES];
    checkInboxTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(checkInbox) userInfo:nil repeats:YES];
}

-(void)showAbout
{
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:self];
}

-(void)checkInbox
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/inbox/unread?access_token=%@&key=%@&filter=withbody", access_token, CLIENT_KEY]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    if (conn) {
        receivedData = [NSMutableData data];
    } else {
        NSLog(@"failed to create connection");
    }
}

-(void)invalidate
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/access-tokens/%@/invalidate", access_token]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:nil];
    if (conn == nil) {
        NSLog(@"failed to create connection");
    }
}

-(void)quit
{
    [NSApp terminate:self];
}

-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    NSURL *url = [[[frame dataSource] request] URL];
    NSLog(@"finished loading %@", [url absoluteString]);
    if (![[url absoluteString] hasPrefix:@"https://stackexchange.com/oauth/login_success"]) {
        return;
    }
    NSString *fragment = [url fragment];
    NSRange r = [fragment rangeOfString:@"access_token="];
    if (r.location == NSNotFound) {
        return;
    }
    r.location += 13;
    NSRange e = [fragment rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&"]];
    if (e.location == NSNotFound) {
        e.location = [fragment length];
    }
    access_token = [fragment substringWithRange:NSMakeRange(r.location, e.location - r.location)];
    [window setIsVisible:NO];
    [self checkInbox];
}

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
    NSLog(@"receive response");
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    id r = [[[SBJsonParser alloc] init] objectWithData:receivedData];
    SBJsonWriter *w = [SBJsonWriter alloc];
    [w setHumanReadable:YES];
    NSLog(@"json %@", [w stringWithObject:r]);
    
    if ([r objectForKey:@"error_id"]) {
        [self doLogin];
        return;
    }
    
    items = [r objectForKey:@"items"];
    
    NSMutableArray *newReadItems = [[NSMutableArray alloc] initWithCapacity:[readItems count]];
    for (unsigned int i = 0; i < [readItems count]; i++) {
        NSString *link = [readItems objectAtIndex:i];
        bool found = false;
        for (unsigned int j = 0; j < [items count]; j++) {
            if ([link isEqualToString:[[items objectAtIndex:j] objectForKey:@"link"]]) {
                found = true;
                break;
            }
        }
        if (found) {
            [newReadItems addObject:link];
        }
    }
    readItems = newReadItems;
    [[NSUserDefaults standardUserDefaults] setObject:readItems forKey:DEFAULTS_KEY_READ_ITEMS];
    
    lastCheck = time(NULL);
    [self resetMenu];
}

-(void)openUrlFromItem:(NSNumber *)index
{
    NSDictionary *msg = [items objectAtIndex:[index unsignedIntValue]];
    NSString *link = [msg objectForKey:@"link"];
    NSLog(@"link %@", link);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:link]];
    NSMutableArray *r = [NSMutableArray arrayWithArray:readItems];
    [r addObject:link];
    readItems = r;
    [[NSUserDefaults standardUserDefaults] setObject:readItems forKey:DEFAULTS_KEY_READ_ITEMS];
    [self resetMenu];
}

@end
