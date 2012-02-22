//
//  Stack_Exchange_NotifierAppDelegate.h
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Stack_Exchange_NotifierAppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *__unsafe_unretained window;
    NSTimer *menuUpdateTimer;
    NSTimer *checkInboxTimer;
    NSMenu *menu;
    NSStatusItem *item;
    WebView *web;
    NSString *access_token;
    NSMutableData *receivedData;
    NSArray *readItems;
    NSArray *items;
    NSMutableArray *targets;
    NSString *loginError;
    time_t lastCheck;
    NSString *lastCheckError;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;

@end
