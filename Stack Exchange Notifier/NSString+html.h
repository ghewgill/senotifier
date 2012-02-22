//
//  NSString+html.h
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 30/01/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (html)
- (NSString *)stringByDecodingXMLEntities;
@end
