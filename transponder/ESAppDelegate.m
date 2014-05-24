//
//  ESAppDelegate.m
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import "ESAppDelegate.h"

#import "SightingPushQueue.h"
#import "LHOAuth2LoginViewController.h"
//#import 
//#import "LIALinkedInApplication.h"
//#import "LIALinkedInHttpClient.h"
//#import "LIALinkedInAuthorizationViewController.h"

@interface ESAppDelegate () <CLLocationManagerDelegate, LHOAuth2LoginViewControllerDelegate>

@property (strong, nonatomic) SightingPushQueue *sightingPushQueue;

@end

@implementation ESAppDelegate
@synthesize sightingPushQueue;


- (void)oAuthViewController:(LHOAuth2LoginViewController *)viewController didSucceedWithCredential:(NSDictionary *)credential
{
    NSLog(@"success with credentials %@", credential);
}
- (void)oAuthViewController:(LHOAuth2LoginViewController *)viewController didFailWithError:(NSError *)error
{
    NSLog(@"error = %@", error);
}

-(void)pushToServer
{
    [sightingPushQueue throttledPost];
}

//- (void)requestMeWithToken:(NSString *)accessToken
//{
//    [self.client getAuthorizationCode:^(NSString *code)
//    {
//        [self.client getAccessToken:code success:^(NSDictionary *accessTokenData)
//        {
//            NSString *accessToken = [accessTokenData objectForKey:@"access_token"];
//            [self requestMeWithToken:accessToken];
//        }                   failure:^(NSError *error) {
//            NSLog(@"Quering accessToken failed %@", error);
//        }];
//    }                      cancel:^{
//        NSLog(@"Authorization was cancelled by user");
//    }                     failure:^(NSError *error) {
//        NSLog(@"Authorization failed %@", error);
//    }];
//}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
////    NSString *requestTokenURLString = @"https://api.linkedin.com/uas/oauth/requestToken";
////    NSString *accessTokenURLString = @"https://api.linkedin.com/uas/oauth/accessToken";
////    NSString *userLoginURLString = @"https://www.linkedin.com/uas/oauth/authorize";
////    NSString *linkedInCallbackURL = @"hdlinked://linkedin/oauth";
//    
//    LHOAuth2LoginViewController *vc =
//    [[LHOAuth2LoginViewController alloc] initWithBaseURL:@"https://myoauth2server"
//                                      authenticationPath:@"/oauth2/authorize/"
//                                                clientID:@"kOAuthClientID"
//                                                   scope:@"read+write"
//                                             redirectURL:@"myapp://oauth2"
//                                                delegate:self];
//    
//    // Wrap it in a nav controller to get navigation bar
//    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:vc];
//    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
////    UINavigationController *navController = self.window.rootViewController;
////    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
//    
//    
//    self.window.rootViewController = navController;
//    // Present view controller
//    //[navController presentViewController:vc animated:YES completion:^() {}];
//    
//    return YES;
//    LIALinkedInApplication *appy = [LIALinkedInApplication applicationWithRedirectURL:@"http://www.google.com"
//                                                                                    clientId:@"75dw0dma8ftq8g"
//                                                                                clientSecret:@"4qvkOmdL2HTRLty5"
//                                                                                       state:@"DCEEFWF45453sdffef424"
//                                                                               grantedAccess:@[@"r_fullprofile", @"r_network"]];
//    self.client = [LIALinkedInHttpClient clientForApplication:appy presentingViewController:nil];
//    
//    [self.client getAuthorizationCode:^(NSString *code)
//    {
//        [self.client getAccessToken:code success:^(NSDictionary *accessTokenData)
//        {
//            NSString *accessToken = [accessTokenData objectForKey:@"access_token"];
//            [self requestMeWithToken:accessToken];
//        } failure:^(NSError *error)
//        {
//            NSLog(@"Quering accessToken failed %@", error);
//        }];
//    }                      cancel:^{
//        NSLog(@"Authorization was cancelled by user");
//    }                     failure:^(NSError *error)
//    {
//        NSLog(@"Authorization failed %@", error);
//    }];
//    
//    return YES;
    self.sightingPushQueue = [[SightingPushQueue alloc] init];
    return YES;
    // Start the transponder broadcasting and receiving. Users will be asked for permissions at this point, if they haven't already accepted them.
    [self.transponder startTransponder];
    
    // Grab the ID, to associate with your own users.
    self.transponderID = self.transponder.transponderID;
    NSLog(@"Transponder initialized. This device has ID %@", self.transponderID);
    
    // Listen for users-in-range updates
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUsers:) name:TransponderDidUpdateUsersInRange object:nil];
    
    // Listen for discovery notification suggestions. You can also listen to `TransponderUserDiscovered` and `TransponderAnonymousUserDiscovered` and roll your own time-and location filtering.
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(sendDiscoverNotification) name:TransponderSuggestsDiscoveryNotification object:nil];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(didDiscoverAnonymousUser) name:TransponderAnonymousUserDiscovered object:nil];
    
    
    return YES;
}

- (void)updateUsers:(NSNotification *)note
{
    // Users are returned in an array
    NSArray *transponderUsers = [note.userInfo objectForKey:@"transponderUsers"];
    NSLog(@"Users in range updated: %@", transponderUsers);
    
    if ([transponderUsers count] == 0) {
        // Badge the app icon
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    }
}

- (void)didDiscoverAnonymousUser
{
//    NSLog(@"Discovered anonymous user");
//    NSLog(@"ok");
    
    // Badge the app icon
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
}

- (void)sendDiscoverNotification
{
    UILocalNotification *notice = [[UILocalNotification alloc] init];
    notice.alertBody = [NSString stringWithFormat:@"Transponder users nearby!"];
    notice.alertAction = @"Converse";
    [[UIApplication sharedApplication] presentLocalNotificationNow:notice];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"appWillEnterBackground" object:nil];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:@"appWillEnterForeground" object:nil];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

// Called when a beacon region is entered
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    NSLog(@"Woke up via app delegate location manager callback");
}

@end
