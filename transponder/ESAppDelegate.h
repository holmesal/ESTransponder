//
//  ESAppDelegate.h
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ESTransponder.h"

@interface ESAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) ESTransponder *transponder;
@property (strong, nonatomic) NSString *transponderID;

@end
