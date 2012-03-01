//
//  Stack_Exchange_NotifierAppDelegate.h
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "Growl/GrowlApplicationBridge.h"

@interface Stack_Exchange_NotifierAppDelegate : NSObject <NSApplicationDelegate, GrowlApplicationBridgeDelegate> {
    NSWindow *__unsafe_unretained window;
    // Timer for periodically updating the menu ("checked n minutes ago")
    NSTimer *menuUpdateTimer;
    // Timer for checking the inbox every 5 minutes
    NSTimer *checkInboxTimer;
    // The menu attached to the status bar item
    NSMenu *menu;
    // The status bar item itself (nil if it's currently hidden)
    NSStatusItem *statusItem;
    // Web view used to log in to the web site
    WebView *web;
    // Access token stored from the login procedure
    NSString *access_token;
    // Accumulated received data from an API request
    NSMutableData *receivedData;
    // Array of all items that we've seen from the server
    NSArray *allItems;
    // Array of items already marked as "read"
    NSArray *readItems;
    // Current unread items from the site
    NSArray *items;
    // Array to hold IndirectTarget objects for menu selections
    NSMutableArray *targets;
    // Error message if we got login errors
    NSString *loginError;
    // Last time inbox was successfully checked
    time_t lastCheck;
    // Error message if we got an error reading the inbox
    NSString *lastCheckError;
    // Whether notifications are enabled
    BOOL notificationsEnabled;
    // Default hide time (minutes)
    long hideIconTime;
    // Icon when no messages
    NSImage *inactiveIcon;
    // Icon when 1+ messages
    NSImage *activeIcon;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;

@end
