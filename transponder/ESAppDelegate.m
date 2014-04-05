//
//  ESAppDelegate.m
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import "ESAppDelegate.h"

@implementation ESAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.transponder = [[ESTransponder alloc] initWithEarshotID:[[UIDevice currentDevice] name] andFirebaseRootURL:@"https://bluetoothtest.firebaseio.com/"];
    // Set the earshot id
//    [self.transponder setEarshotID:@"alonso-set-this-id"];
//    self.transponder.earshotID = [[UIDevice currentDevice] name];
//    [self.transponder initFirebase:@"https://bluetoothtest.firebaseio.com/"];
    [self.transponder startDetecting];
    [self.transponder startBroadcasting];
    
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    [self.transponder resetBluetooth];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [self.transponder chirpBeacon];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
