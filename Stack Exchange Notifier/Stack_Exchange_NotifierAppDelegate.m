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

// API client key, specific to each API client
// (don't use this one, register to get your own
// at http://stackapps.com/apps/oauth/register )
NSString *CLIENT_KEY = @"JBpdN2wRVnHTq9E*uuyTPQ((";
// Name of key to store read items in defaults
NSString *DEFAULTS_KEY_READ_ITEMS = @"com.hewgill.senotifier.readitems";

// Local function prototypes

NSString *timeAgo(time_t t);
NSStatusItem *createStatusItem(void);
void setMenuItemTitle(NSMenuItem *menuitem, NSDictionary *msg, bool highlight);

// Simple implementation of "checked n minute(s)/hour(s) ago"
// for use in the menu
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

// IndirectTarget can be attached to a menu item (or anything that calls
// a "fire" selector) to pass through an additional argument to a selector
// that eventually handles the selection. Note that since NSMenuItem doesn't
// retain its "fire" target, you will need to keep a reference to these
// somewhere yourself ("targets" array here).
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
    // Turn off clang diagnostics because we're using performSelector here,
    // so ARC can't be sure we aren't calling retain or release.
    // (Don't try to do that.)
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_originalTarget performSelector:_action withObject:_arg];
    #pragma clang diagnostic pop
}

@end

// Create the status item when needed. Called on program startup or
// when the icon is unhidden.
NSStatusItem *createStatusItem(void)
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    NSStatusItem *item = [bar statusItemWithLength:NSVariableStatusItemLength];
    [item setImage:[[NSImage alloc] initByReferencingFile:[[NSBundle mainBundle] pathForResource:@"favicon.ico" ofType:nil]]];
    [item setHighlightMode:YES];
    return item;
}

// Utility function to set an inbox item menu item.
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

// Update the menu periodically (every 30 seconds) to show the
// amount of time since the last check. Also shows error messages
// if available.
-(void)updateMenu
{
    NSDictionary *normalattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
        nil];
    NSMutableAttributedString *at = [[NSMutableAttributedString alloc] initWithString:@"Log in" attributes:normalattrs];
    if (loginError != nil) {
        NSDictionary *redattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
            [NSColor redColor], NSForegroundColorAttributeName,
            nil];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:@" - " attributes:redattrs]];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:loginError attributes:redattrs]];
    }
    [[menu itemAtIndex:1] setAttributedTitle:at];
    
    at = [[NSMutableAttributedString alloc] initWithString:@"Check Now" attributes:normalattrs];
    if (lastCheckError != nil) {
        NSDictionary *redattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
            [NSColor redColor], NSForegroundColorAttributeName,
            nil];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:@" - " attributes:redattrs]];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:lastCheckError attributes:redattrs]];
    } else if (lastCheck) {
        NSDictionary *grayattrs = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSFont menuBarFontOfSize:0.0], NSFontAttributeName,
            [NSColor grayColor], NSForegroundColorAttributeName,
            nil];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:timeAgo(lastCheck) attributes:grayattrs]];
    }
    [[menu itemAtIndex:2] setAttributedTitle:at];
}

// Completely reset the menu, creating a new one and add all items
// back in to the menu. Called when the list of inbox items changes.
// There is probably a more elegant way to modify just the part of
// the menu that needs to change, but this works fine.
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
            NSImage *icon = [[NSImage alloc] initByReferencingURL:[[NSURL alloc] initWithString:[[obj objectForKey:@"site"] objectForKey:@"icon_url"]]];
            NSSize size;
            size.height = 24;
            size.width = 24;
            [icon setSize:size];
            [it setImage:icon];
            IndirectTarget *t = [[IndirectTarget alloc] initWithArg:[NSNumber numberWithUnsignedInt:i] action:@selector(openUrlFromItem:) originalTarget:self];
            // must store the IndirectTarget somewhere to retain it, because
            // NSMenuItem won't do that for us
            [targets addObject:t];
            [it setTarget:t];
            [menu addItem:it];
            i++;
        }
    } else {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"no messages" action:NULL keyEquivalent:@""]];
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Hide for 25 minutes" action:@selector(hideIcon) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Invalidate login token" action:@selector(invalidate) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit) keyEquivalent:@""]];

    // update annotations such as "checked n minutes ago"
    [self updateMenu];
    
    if (statusItem != nil) {
        // if there are any unread items, display that number on the status bar
        if (unread > 0) {
            [statusItem setTitle:[NSString stringWithFormat:@"%u", unread]];
        } else {
            [statusItem setTitle:nil];
        }
        [statusItem setMenu:menu];
    }
}

// Open a window to log in to Stack Exchange.
-(void)doLogin
{
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    // this URL includes the
    //     client_id = 81 (specific to this application)
    //     scope = read_inbox (tell the user we want to read their inbox contents)
    //     redirect_uri = where to send the browser when authentication succeeds
    [[web mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://stackexchange.com/oauth/dialog?client_id=81&scope=read_inbox&redirect_uri=https://stackexchange.com/oauth/login_success"]]];
}

// Initialise the application.
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    lastCheck = 0;
    loginError = nil;
    lastCheckError = nil;

    // read the list of items already read from defaults
    readItems = [[NSUserDefaults standardUserDefaults] arrayForKey:DEFAULTS_KEY_READ_ITEMS];

    // create the status bar item
    statusItem = createStatusItem();
    [self resetMenu];

    // create the web view that we will use for login
    web = [[WebView alloc] initWithFrame:[window frame]];
    [window setContentView:web];
    [web setFrameLoadDelegate:self];

    // kick off a login procedure
    [self doLogin];

    // set up the timers
    menuUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(updateMenu) userInfo:nil repeats:YES];
    checkInboxTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(checkInbox) userInfo:nil repeats:YES];
}

// Show a standard About panel.
-(void)showAbout
{
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:self];
}

// Check for new inbox items on the server.
// Call is ignored if the status item is currently hidden
// (we wouldn't show the menu items anyway in that state).
-(void)checkInbox
{
    if (statusItem == nil) {
        return;
    }
    lastCheckError = nil;
    [self updateMenu];
    // Ask for new inbox items from the server. Use "withbody"
    // filter to get a small bit of the body text (to display
    // in the menu).
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/inbox/unread?access_token=%@&key=%@&filter=withbody", access_token, CLIENT_KEY]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    if (conn) {
        receivedData = [NSMutableData data];
    } else {
        NSLog(@"failed to create connection");
    }
}

// Hide the status item icon, setting a timer for 25
// minutes to show it again.
-(void)hideIcon
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    [bar removeStatusItem:statusItem];
    statusItem = nil;
    [NSTimer scheduledTimerWithTimeInterval:25*60 target:self selector:@selector(showIcon) userInfo:nil repeats:NO];
}

// Show the status icon after the hiding timeout and
// check for new inbox items straight away.
-(void)showIcon
{
    statusItem = createStatusItem();
    [self resetMenu];
    [self checkInbox];
}

// Invalidate login token on the server. Might help with debugging.
-(void)invalidate
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/access-tokens/%@/invalidate", access_token]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:nil];
    if (conn == nil) {
        NSLog(@"failed to create connection");
    }
}

// Arrivederci.
-(void)quit
{
    [NSApp terminate:self];
}

// Called from the WebView when there is an error of some kind
// and we can't reach the server.
-(void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    loginError = [error localizedDescription];
    [self updateMenu];
    [[NSAlert alertWithError:error] runModal];
    // There isn't anything on the web page for the user to interact with
    // at this point, so close the view.
    [window setIsVisible:NO];
}

// Called from the WebView when there is an error of some kind
// during the login process.
-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    loginError = [error localizedDescription];
    [self updateMenu];
    [[NSAlert alertWithError:error] runModal];
    // There might be something the user wants to read in this case,
    // so don't close the view.
    //[window setIsVisible:NO];
}

// Finished the login process. The server sends the browser to
// the URL specified in the login request ("redirect_uri" in doLogin)
// so we detect that specific URL and get the authentication token.
-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    // Get the current URL from the frame.
    NSURL *url = [[[frame dataSource] request] URL];
    NSLog(@"finished loading %@", [url absoluteString]);
    // Make sure we've ended up at the "login success" page
    if (![[url absoluteString] hasPrefix:@"https://stackexchange.com/oauth/login_success"]) {
        loginError = @"Error logging in to Stack Exchange.";
        return;
    }
    // Extract the access_token value from the URL
    NSString *fragment = [url fragment];
    NSRange r = [fragment rangeOfString:@"access_token="];
    if (r.location == NSNotFound) {
        loginError = @"Access token not found on login.";
        return;
    }
    r.location += 13;
    NSRange e = [fragment rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&"]];
    if (e.location == NSNotFound) {
        e.location = [fragment length];
    }
    access_token = [fragment substringWithRange:NSMakeRange(r.location, e.location - r.location)];
    // Close the window, we're done with it.
    [window setIsVisible:NO];
    // Clear any login error, since it succeeded this time.
    loginError = nil;
    // Finally, check the inbox now that we're logged in.
    [self checkInbox];
}

// Connection error of some kind when sending inbox request.
-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    lastCheckError = [error localizedDescription];
    [self updateMenu];
}

// Started to receive an API response from the server.
-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
}

// Received some more data from the server for an API request.
-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

// Finished receiving and API response. Parse the JSON and
// reset the menu.
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    // Parse the JSON response to the API request
    id r = [[[SBJsonParser alloc] init] objectWithData:receivedData];
    
    // Write the response to the log for debugging
    SBJsonWriter *w = [SBJsonWriter alloc];
    [w setHumanReadable:YES];
    NSLog(@"json %@", [w stringWithObject:r]);
    
    // If we got an error, try logging in again.
    if ([r objectForKey:@"error_id"]) {
        [self doLogin];
        return;
    }
    
    // Get the unread inbox items according to the server.
    items = [r objectForKey:@"items"];
    
    // We only need to keep the "read" items in our local defaults
    // list for those items where the server still thinks they're
    // unread. Trim out local items that no longer appear in the
    // server's unread list.
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
    
    // Remember the last time we checked the inbox.
    lastCheck = time(NULL);
    [self resetMenu];
}

// Selector called by IndirectTarget when the user selects
// an inbox item from the menu.
-(void)openUrlFromItem:(NSNumber *)index
{
    // Get the item by index
    NSDictionary *msg = [items objectAtIndex:[index unsignedIntValue]];
    // Get the link for the item
    NSString *link = [msg objectForKey:@"link"];
    NSLog(@"link %@", link);
    // Open the link in the user's default browser
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:link]];
    // Add this item to our local read items list and store it
    NSMutableArray *r = [NSMutableArray arrayWithArray:readItems];
    [r addObject:link];
    readItems = r;
    [[NSUserDefaults standardUserDefaults] setObject:readItems forKey:DEFAULTS_KEY_READ_ITEMS];
    // Update the menu since we now have one fewer unread item
    [self resetMenu];
}

@end
