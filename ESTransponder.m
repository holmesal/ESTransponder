//
//  ESTransponder.m
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import "ESTransponder.h"
//#import <Firebase/Firebase.h>
//#import <Mixpanel/Mixpanel.h>

// Extensions
#import "CBCentralManager+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBUUID+Ext.h"

#import "TransponderViewController.h"
#import "Math.h"

#import "SightingPushQueue.h"

#define DEBUG_CENTRAL NO
#define DEBUG_PERIPHERAL YES
#define DEBUG_BEACON YES
#define DEBUG_USERS NO
#define DEBUG_TIMEOUTS NO
#define DEBUG_NOTIFICATIONS NO
#define IS_RUNNING_ON_SIMULATOR NO

#define TIMEOUT 30.0 // How old should a user be before I consider them gone?

#define MAX_BEACON 19 // How many beacons to use (IOS max 19)
#define REPORTING_INTERVAL 12.0 // How often to report to firebase
#define BACKGROUND_REPORTING_INTERVAL 3.0 // How often to report, when in the background
#define BEACON_TIMEOUT 10.0 // How long to range when a beacon is discovered (background only)
#define NOTIFICATION_TIMEOUT 1200.0 // Minimum time between sending discover notifications
#define CHIRP_LENGTH 10.0 // How long to chirp for? NOTE - might take up to 40 seconds more for other devices to exit the region

#define REPORT_FAILURE_IN_STACK_TIMEOUT 2.0f
@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate>

@property (nonatomic) BOOL bluetoothWasTried;
@property (nonatomic) BOOL coreLocationWasTried;
// Bluetooth / main class stuff
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSDictionary *bluetoothAdvertisingData;
@property (strong, nonatomic) NSMutableDictionary *bluetoothUsers;

// Mixpanel
//@property (strong, nonatomic) Mixpanel *mixpanel;

@property (nonatomic, readonly) BOOL isDetecting;
@property (nonatomic, readonly) BOOL isBroadcasting;

// Beacon broadcasting
@property NSInteger flipCount;
@property BOOL currentlyChirping;
@property BOOL flippingBreaker;
@property BOOL isFlipping;
@property (strong, nonatomic) CLBeaconRegion *chirpBeaconRegion;
@property (strong, nonatomic) NSDictionary *chirpBeaconData;
@property (strong, nonatomic) NSDictionary *identityBeaconData;

// Beacon monitoring
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) NSMutableArray *regions;
@property (strong, nonatomic) NSArray *regionUUIDS;
@property (strong, nonatomic) CLBeaconRegion *rangingRegion;
@property (strong, nonatomic) NSTimer *rangingTimeout;
@property (nonatomic, readonly) BOOL hasSentErrorNote;

// Firebase-synced users array
//@property (strong, nonatomic) Firebase *rootRef;
//@property (strong, nonatomic) Firebase *earshotUsersRef;
@property (strong, nonatomic) NSMutableDictionary *earshotUsers;
@property (strong, nonatomic) NSTimer *filterTimer;
@property (strong, nonatomic) NSMutableDictionary *lastReported;
@property (assign, nonatomic) BOOL actuallyRemove;
@property (strong, nonatomic) NSDate *lastNotificationEvent;

//when timer is up, it fires a failure message for the stack.  This must be interupted if success occurs sooner.
@property (strong, nonatomic) NSTimer *reportStackFailureTimer;

// Location filtering
@property (assign, nonatomic) BOOL okayToSendAnonymousNotification;
//@property (strong, nonatomic) Firebase *seenRef;
@property (strong, nonatomic) NSMutableArray *seen;

// Oscillator
@property NSInteger broadcastMode;

@property (strong, nonatomic) SightingPushQueue *sightingPushQueue;

@end

@implementation ESTransponder
@synthesize transponderID;
//@synthesize peripheralManagerIsRunning;
@synthesize isRunning;
@synthesize sightingPushQueue;

static ESTransponder *sharedTransponder;
+(ESTransponder *)sharedInstance
{
    if (!sharedTransponder)
    {
        sharedTransponder = [[ESTransponder alloc] init];
    }
    
    return sharedTransponder;
}

//when timer is up, it fires a failure message for the stack.  This must be interupted if success occurs sooner.
@synthesize reportStackFailureTimer;

+(BOOL)HasBeaconID
{
    id transponderId = [[NSUserDefaults standardUserDefaults] objectForKey:@"transponder-beaconID"];
    return (transponderId) ? YES : NO;
}
+(BOOL)HardwareIsSupportedOnDevice
{
    CBCentralManager *cbcentralManager = [[CBCentralManager alloc] init];
    

    BOOL BLESupport = ([cbcentralManager state] != CBCentralManagerStateUnsupported);

    
    return BLESupport;
}

+(void)PresentTransponderAuthFlowFromViewController:(UIViewController*)viewController withCompletion:(void(^)(NSError *error))completion
{
    if ([viewController isKindOfClass:[UIViewController class]])
    {
        UIViewController *tvc = [[TransponderViewController alloc] initWithCompletionBlock:completion];
        [viewController presentViewController:tvc animated:YES completion:^{}];
    } else
    {
        NSLog(@"Fatal error %@.  The sender, '%@', must by kind of UIViewController.", @"PresentTransponderAuthFlowFromViewController:withCompletion:", viewController);
    }
}

-(ESTransponder*)init
{
    if (self = [super init])
    {
        //intialize the push queue which will store data in core data until such time as it reaches the server
        self.sightingPushQueue = [[SightingPushQueue alloc] init];
        // Generate a new id, or use an existing one
        self.transponderID = [self getOrGenerateID];
        self.identifier = [CBUUID UUIDWithString:IDENTIFIER_STRING];
        self.bluetoothUsers = [[NSMutableDictionary alloc] init];
        self.transponderUsers = [[NSArray alloc] init];
        self.lastReported = [[NSMutableDictionary alloc] init];
        self.seen = [[NSMutableArray alloc] init];
        //        self.mixpanel = [Mixpanel sharedInstance];
        // Set up the allowed beacon regions
        // What are the uuids?
//        self.regionUUIDS = @[      @"DDE6C09F-345B-4FC2-80C1-C27977EB35A6", // Shortwave uuids
//                                   @"E20DF868-0B06-4361-85DE-EE57A57CAA5F",
//                                   @"BCEA644E-3B51-4E6C-8B72-ED204EC5FA36",
//                                   @"9CA603ED-7A5D-4F2F-BBB6-70AAC0050C7E",
//                                   @"A97C54AA-A7B8-4AED-8542-12BCF12D97DD",
//                                   @"6B6ABB05-46D1-4466-BCAC-D6F70CBE1348",
//                                   @"F1229A67-42EB-40CB-83F0-32385074F705",
//                                   @"259CB377-2CB2-476B-B59A-326CB3315B47",
//                                   @"C0A151D2-EC1D-4547-87D8-4C73E94252D3",
//                                   @"D64BB228-C3C1-4A16-A1A5-C84785DAAD7B",
//                                   @"2DC4D09C-5846-463D-9FFC-BDFE414417BF",
//                                   @"5AAFB50C-F795-4818-9433-7197C517B1E0",
//                                   @"155E22AE-AE03-4A65-B665-71D9E417146A",
//                                   @"19D0C85F-B85E-4DE1-9449-498F62E443FD",
//                                   @"554EBF21-D361-41F0-8B93-34E40ABB090B",
//                                   @"B8F2B4F6-2771-4B05-BB8B-CBA06A08CC74",
//                                   @"43AF147A-2EC5-4357-AD56-AB36B145C2F5",
//                                   @"A7CF1269-E65C-4BED-9395-183761DE02DB",
//                                   @"9C9FA6DD-B314-429E-A587-37EAA0C5D6B7"];
        
        self.regionUUIDS = @[      @"53324C49-54F5-433D-B87D-3350578F144D",
                                   @"EC3488B8-2EE0-4EA8-9E0E-A96973B50DF8",
                                   @"82BB21D5-937A-484A-9682-A6869ADA3E86",
                                   @"BB4EBDA7-EDE6-4704-98B3-841A356637B1",
                                   @"FBAEE41C-CC46-4DDA-9778-8F8C2A8D9D50",
                                   @"E1A5EB08-CAC5-4039-9FEA-C7325AE79886",
                                   @"7999BD85-4CAE-4009-9664-0BC044030E7B",
                                   @"C5B35AC6-0E03-4D2B-B871-71718A10ADBE",
                                   @"0729808A-29FB-4EAF-BF20-2665EDBAB24D",
                                   @"A9B7573B-04FF-46A7-A724-84325E89F506",
                                   @"88A38AA7-1C3D-4FB4-B798-F60F7DCBA445",
                                   @"AC1B7CE1-F1D0-4694-800E-1185CDAC73FF",
                                   @"65FA6EAB-2F77-43FF-902E-94934B3A629C",
                                   @"47D4A312-824B-4641-AF22-BDE0D8A93F97",
                                   @"FC1AF90C-24D3-4BDE-855A-068976FC9F7E",
                                   @"DC9466FE-EBA1-4EBB-BC56-8F5397C1590B",
                                   @"3B9EB05B-5865-413F-A61B-3AA78721CFF5",
                                   @"A2F510C4-B75D-4F92-8E9B-242E227B1C0C",
                                   @"911C9FE9-3FF4-4768-A76F-01864C35B6F7"];
        // Setup the firebase
//        [self initFirebase:@"https://transponder.firebaseio.com"];
        // Create the identity iBeacon
        [self initIdentityBeacon:self.transponderID];
        // Start off NOT flipping between identity beacon / chirping beacon
        self.currentlyChirping = NO;
        // Start off okay to send anonymous notificatoins
        self.okayToSendAnonymousNotification = YES;
        // Start off with a broadcast mode of 0
        self.broadcastMode = 0;
        // Chirp another beacona  few times to wake up other users
        //        [self chirpBeacon];
        // Start the timer to filter the users
//        [self startFilterTimer];
        // Start a repeating timer to broadcast as an iBeacon, every 30 seconds
        // Listen for chirpBeacon events
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chirpBeacon) name:kTransponderTriggerChirpBeacon object:nil];
        // Listen for app sleep events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
        // Listen for app wakeup events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterBackground) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}

- (NSString *)getOrGenerateID
{
    // Check NSUserDefaults for a saved ID
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *existingID = [prefs valueForKey:@"transponder-beaconID"];
    
    if (existingID){
        // Return the id
        return existingID;
    } else {
        // Generate an id
        NSAssert(NO, @"Developers are expected to go through the auth flow, before creating ESTransponder instances");
//        NSInteger idInt = esRandomNumberIn(0, 99999999);
//        NSString *stringId = [NSString stringWithFormat:@"%ld",(long)idInt];
//        [prefs setValue:stringId forKey:@"transponderID"];
//        [prefs synchronize];
//        return stringId;
    }
    return nil;
}

// Shorthand for startDetecting, startBroadcasting, and chirpBeacon
- (void)startTransponder
{
    NSLog(@"Starting via startAwesome");
    [self startBroadcasting];
    [self startDetecting];
}

// Send a local notification for deep background debugging
- (void)debugNote:(NSString *)text
{
    if (SHOW_DEBUG_NOTIFICATIONS) {
        UILocalNotification *notice = [[UILocalNotification alloc] init];
        notice.alertBody = text;
        notice.alertAction = @"Open";
        [[UIApplication sharedApplication] presentLocalNotificationNow:notice];
    }
}

- (void)pruneUsers
{
    // Only do this if you're in the foreground
    UIApplication *application = [UIApplication sharedApplication];
    
    if (application.applicationState == UIApplicationStateActive) {
        
        if (DEBUG_USERS) NSLog(@"Pruning BLE users!");
        
        // WHATTIMEISITRIGHTNOW.COM
        NSDate *now = [[NSDate alloc] init];
        // Check every user
        for(NSString *userBeaconKey in [self.bluetoothUsers.allKeys copy])
        {
            NSMutableDictionary *userBeacon = [self.bluetoothUsers objectForKey:userBeaconKey];
            // How long ago was this?
            float lastSeen = [now timeIntervalSinceDate:[userBeacon objectForKey:@"lastSeen"]];
            if (DEBUG_USERS) NSLog(@"time interval for %@ -> %f",[userBeacon objectForKey:@"transponderID"],lastSeen);
            // If it's longer than 20 seconds, they're probs gone
            if (lastSeen > TIMEOUT)
            {
                if (DEBUG_USERS) NSLog(@"Removing user: %@",userBeacon);
                // Remove from earshotUsers, if it's actually in there
                //            if ([userBeacon objectForKey:@"transponderID"] != [NSNull null]) {
                //                [self removeUser:[userBeacon objectForKey:@"transponderID"]];
                //            }
                // Remove from bluetooth users
                [self.bluetoothUsers removeObjectForKey:userBeaconKey];
            } else {
                if (DEBUG_USERS) NSLog(@"Not removing user: %@",userBeacon);
            }
        }
    } else {
        if (DEBUG_USERS) NSLog(@"Not pruning BLE users - app is in the background");
    }
    
}

//- (void)initFirebase:(NSString *)baseURL
//{
//    self.earshotUsers = [[NSMutableDictionary alloc] init];
//    self.rootRef = [[Firebase alloc] initWithUrl:baseURL];
//    self.earshotUsersRef = [[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:self.transponderID] childByAppendingPath:@"tracking"];
//    [self.earshotUsersRef observeEventType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot)
//     {
//         // Update the locally-stored earshotUsers array
//         NSLog(@"Got data from firebase");
//         NSLog(@"%@",snapshot.value);
//         if (snapshot.value != [NSNull null]){
//             self.earshotUsers = [NSMutableDictionary dictionaryWithDictionary:snapshot.value];
//         } else
//         {
//             self.earshotUsers = [[NSMutableDictionary alloc] init];
//             self.lastReported = [[NSMutableDictionary alloc] init];
//         }
//         // Filter the users based on timeout
//         [self filterFirebaseUsers];
//         // Emit the updated users
//         [self emitUsers];
//     }];
//}
//
//- (void)emitUsers
//{
//    // Filter the current users into an array
//    NSMutableArray *formatted = [[NSMutableArray alloc] init];
//    
//    for (NSString *uuid in [self.earshotUsers allKeys])
//    {
//        NSNumber *lastSeen = [self.earshotUsers objectForKey:uuid];
//        NSDictionary *formattedUser = @{@"uuid": uuid,
//                                        @"lastSeen": lastSeen};
//        [formatted addObject:formattedUser];
//    }
//    
//    NSArray *output = [NSArray arrayWithArray:formatted];
//    
//    // Store the users
//    self.transponderUsers = output;
//    
//    // Emit the users
//    [[NSNotificationCenter defaultCenter] postNotificationName:TransponderDidUpdateUsersInRange object:self userInfo:@{@"transponderUsers":output}];
//}
//
//- (void)filterFirebaseUsers
//{
//    if (DEBUG_USERS) NSLog(@"Filtering firebase users with actuallyRemove = %d",self.actuallyRemove);
//    // Store the current time
//    NSDate *currentDate = [NSDate date];
//    // Track whether a user to remove was found
//    BOOL removeUserInTheFuture = NO;
//    for (NSString *userKey in self.earshotUsers) {
//        // If the timeout is too old, clear it out
//        NSNumber *timestampNumber = [self.earshotUsers objectForKey:userKey];
//        // Protect against weird values here
//        if ([timestampNumber isKindOfClass:[NSNumber class]]) {
//            long timestamp = [timestampNumber longValue];
//            
//            NSDate *beforeDate = [[NSDate alloc] initWithTimeIntervalSince1970:timestamp];
//            
//            NSTimeInterval interval = [currentDate timeIntervalSinceDate:beforeDate];
//            
//            NSLog(@"Long filter timeout for user %@ --> %f",userKey,interval);
//            
//            if (interval > TIMEOUT)
//            {
//                NSLog(@"Lost user %@ - has been too long: %f",userKey,interval);
//                if (self.actuallyRemove) {
//                    // Remove the user
//                    [self removeUser:userKey];
//                } else{
//                    // Remove this user the next time through
//                    removeUserInTheFuture = YES;
//                }
//                
//            }
//        } else {
//            // There's a weird value here
//            [self removeUser:userKey];
//        }
//    }
//    
//    // If we just removed stuff, set actually remove back to NO for the regularly scheduled program
//    if (self.actuallyRemove) {
//        self.actuallyRemove = NO;
//    }
//    
//    // If we found a user to remove, then set an interval for a few seconds from now and set actually remove to true
//    if (removeUserInTheFuture) {
//        // Chirp the beacon to see if you can get dem users back.
//        [self chirpBeacon];
//        // set actually remove for the next run through
//        self.actuallyRemove = YES;
//        // Call this again in a couple of seconds, at which point the user will be actually removed
//        [self performSelector:@selector(filterFirebaseUsers) withObject:nil afterDelay:10.0];
//    }
//}
//
//- (void)startFilterTimer
//{
//    if (self.filterTimer) {
//        [self.filterTimer invalidate];
//    }
//    self.filterTimer = [NSTimer timerWithTimeInterval:TIMEOUT target:self selector:@selector(filterFirebaseUsers) userInfo:nil repeats:YES];
//    [[NSRunLoop mainRunLoop] addTimer:self.filterTimer forMode:NSDefaultRunLoopMode];
//}
//
//// Takes in a bluetooth or iBeacon user and adds it to earshotUsers
//- (void)addUser:(NSString *)userID
//{
//    //    NSLog(@"Adding user to firebase: %@",userID);
//    //    // Get the rounded date/time
//    //    uint rounded = [self roundTime:[[NSDate date] timeIntervalSince1970]];
//    //    // Add the user for yourself
//    //    [[self.earshotUsersRef childByAppendingPath:userID] setValue:[[NSNumber alloc] initWithInt:rounded]];
//    //    // Add yourself for the user
//    //    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.transponderID] setValue:[[NSNumber alloc] initWithInt:rounded]];
//    //    [self.lastReported setObject:[[NSNumber alloc] initWithDouble:now] forKey:userID];
//    //    NSLog(@"Rounded time is %d",rounded);
//    uint now = [[NSDate date] timeIntervalSince1970];
//    // Make sure it's not the time we already have
//    NSNumber *last = [self.lastReported objectForKey:userID];
//    uint then = [last intValue];
//    //    NSLog(@"Time difference for user %@ is %u",userID,(now - then));
//    uint howLong = now - then;
//    if (howLong > REPORTING_INTERVAL)
//    {
//        if(DEBUG_USERS) NSLog(@"Adding/updating user on firebase: %@",userID);
//        // Add the user for yourself
//        [[self.earshotUsersRef childByAppendingPath:userID] setValue:[[NSNumber alloc] initWithInt:now]];
//        // Add yourself for the user
//        [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.transponderID] setValue:[[NSNumber alloc] initWithInt:now]];
//        [self.lastReported setObject:[[NSNumber alloc] initWithInt:now] forKey:userID];
//        
//        
//        // Also add them to the seen array if you haven't before
//        // Only send if we haven't seen this user before
//        NSUInteger index = [self.seen indexOfObject:userID];
//        if (index == NSNotFound)
//        {
//            // Add this user as seen
//            [self.seen addObject:userID];
//            // Sync to firebase
//            //            [self.seenRef setValue:self.seen];
//        }
//    } else {
//        if(DEBUG_TIMEOUTS) NSLog(@"Timeout not long enough, doing nothing.");
//    }
//    
//    
//}

- (uint)roundTime:(NSTimeInterval)time
{
    // Round to the nearest 5 seconds
    //    NSLog(@"time = %f", time);
    double rounded = REPORTING_INTERVAL * floor((time/REPORTING_INTERVAL)+0.5);
    return rounded;
}

//- (void)removeUser:(NSString *)userID
//{
//#warning not sure this is the right way to handle removing users...
//#warning - add feature to not remove this user if it exists elsewhere in the bluetooth array
//    // Only do this if you're in the foreground
//    UIApplication *application = [UIApplication sharedApplication];
//    
//    if (application.applicationState == UIApplicationStateActive) {
//        // Remove the user for yourself
//        [[self.earshotUsersRef childByAppendingPath:userID] removeValue];
//    }
//    // Remove yourself for the user
//    //    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.transponderID] removeValue];
//}



# pragma mark - FOREGROUND vs BACKGROUND modes
- (void)appWillEnterForeground
{
    NSLog(@"Transponder -- App is entering foreground");
    // Start ranging beacons in Region 19
    [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
    // Start flipping between an iBeacon and a BLE peripheral
    // If you aren't already
    if (self.peripheralManager.state == CBPeripheralManagerStatePoweredOn){
        [self startAdvertising];
    }
    // Chirp the discovery iBeacon for a few seconds
    [self chirpBeacon];
    // Update the date we use for the notification timeout
    self.lastNotificationEvent = [NSDate date];
}

- (void)appWillEnterBackground
{
    NSLog(@"Transponder -- App is entering background");
    // Stop acting as a beacon
    [self.peripheralManager stopAdvertising];
    // Stop chirping as a beacon
    [self stopChirping];
//    // Start advertising only as a BLE peripheral
    [self stopFlipping];
//    // Stop ranging beacons
//    [self stopRanging];
//    // Pause the filter timer
//    //    self.filterTimer
}

# pragma mark - core bluetooth

- (void)startDetecting
{
    NSLog(@"startDetecting called");
    // Setup beacon monitoring for regions
    [self setupBeaconRegions];
    // Listen for major location changes
    [self.locationManager startMonitoringSignificantLocationChanges];
    // Listen for bluetooth LE
    [self startDetectingTransponders];
}

- (void)startBroadcasting
{
    NSLog(@"startBroadcast called");
    [self startBluetoothBroadcast];
    
}

- (void)startDetectingTransponders
{
    if (!self.centralManager)
        NSLog(@"New central created");
    self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    // Uncomment this timer if you need to report ranges in a timer
    //    detectorTimer = [NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL target:self
    //                                                   selector:@selector(reportRanges:) userInfo:nil repeats:YES];
}

- (void)startBluetoothBroadcast
{
    // start broadcasting if it's stopped
    if (!self.peripheralManager) {
        [self debugNote:@"Transponder is booting bluetooth + iBeacon"];
        self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    }
}

- (void)startScanning
{
    
    NSDictionary *scanOptions = @{CBCentralManagerScanOptionAllowDuplicatesKey:@(YES)};
    
    [self.centralManager scanForPeripheralsWithServices:@[self.identifier] options:scanOptions];
    _isDetecting = YES;
    if (DEBUG_CENTRAL) NSLog(@"Scanning!");
}

- (void)startAdvertising
{
    
    // For some reason, removing call to the BLE stack and starting to broadcast as iBeacon seems to work.
    
//    self.bluetoothAdvertisingData = @{CBAdvertisementDataServiceUUIDsKey:@[self.identifier], CBAdvertisementDataLocalNameKey:self.transponderID};
//    
//    // Start advertising over BLE
//    [self debugNote:@"Transponder is broadcasting"];
//    [self.peripheralManager startAdvertising:self.bluetoothAdvertisingData];
    
    [self chirpBeacon];
    // Start flipping between the identity beacon and BLE
    [self startFlipping];
}


#pragma mark - CBCentralManagerDelegate
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    if (DEBUG_CENTRAL) {
        NSLog(@"did discover peripheral: %@, data: %@, %1.2f", [peripheral.identifier UUIDString], advertisementData, [RSSI floatValue]);
        
        CBUUID *uuid = [advertisementData[CBAdvertisementDataServiceUUIDsKey] firstObject];
        NSLog(@"service uuid: %@", [uuid representativeString]);
    }
    
    // Create a user if there isn't one
    NSMutableDictionary *existingUser = [self.bluetoothUsers objectForKey:[peripheral.identifier UUIDString]];
    if ([existingUser count] == 0) {
        // No user yet, make one
        NSMutableDictionary *newUser = [[NSMutableDictionary alloc] initWithDictionary:@{@"lastSeen": [[NSDate alloc] init],
                                                                                         @"transponderID": [NSNull null]}];
        // Insert
        [self.bluetoothUsers setObject:newUser forKey:[peripheral.identifier UUIDString]];
        
        // Alias
        existingUser = newUser;
        
        // Send a local notification to tell the user we discovered a device
        [self sendAnonymousNotification];
        
        // Send the new (anonymous) user notification
        //        [[NSNotificationCenter defaultCenter] postNotificationName:kTransponderEventNewUserDiscovered object:self userInfo:@{@"user":existingUser}];
        
        // Chirp the beacon!
        [self chirpBeacon];
    } else{
        // Update the time last seen
        [existingUser setObject:[[NSDate alloc] init] forKey:@"lastSeen"];
    }
    
    // Update local name if included in advertisement
    NSString *localName = [advertisementData valueForKey:@"kCBAdvDataLocalName"];
    if (localName){
        [existingUser setValue:localName forKey:@"transponderID"];
        // Add to transponder users
    }
    
    // If it has a local name (whether just set or actively being broadcast), call addUser
    NSString *userID = [existingUser objectForKey:@"transponderID"];
    if (userID && userID != (NSString*)[NSNull null])
    {
        //        NSLog(@"%@ addUser %@ <centralManager:didDiscoverPeripheral:advertisementData:RSSI:>", [FCUser owner].id, userID);
//        [self addUser:userID];
        // Add the sighting to the post queue
        [self sightedBroadcaster:userID withRSSI:RSSI];
        [self sendUserDiscoverEvent:userID];
    } else {
        [self sendAnonymousUserDiscoverEvent];
    }
    
    if (DEBUG_CENTRAL) NSLog(@"%@",self.bluetoothUsers);
    
    // Notify peeps that an transponder user was discovered
//    [[NSNotificationCenter defaultCenter] postNotificationName:kTransponderEventTransponderUserDiscovered
//                                                        object:self
//                                                      userInfo:@{@"user":existingUser,
//                                                                 @"identifiedUsers":self.earshotUsers,
//                                                                 @"bluetoothUsers":self.bluetoothUsers}];
    
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (DEBUG_CENTRAL) NSLog(@"-- central state changed: %@", self.centralManager.stateString);
    if (central.state == CBCentralManagerStateUnknown)
    {
        return;
    }
    
    /*
     CBCentralManagerStateResetting,1
     CBCentralManagerStateUnsupported,2
     CBCentralManagerStateUnauthorized,3
     CBCentralManagerStatePoweredOff,4
     CBCentralManagerStatePoweredOn,5
     */
    NSLog(@"central.state = %d", self.centralManager.state);
    
    // Emit the state, if state != unknown
    if (central.state)
    {
        self.bluetoothWasTried = YES;
        [self emitBluetoothState];
    }
    // If powered on, start scanning
    if (central.state == CBCentralManagerStatePoweredOn)
    {
        [self startScanning];
    }
    
    
}

#pragma mark - CBPeripheralManagerDelegate
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    if (DEBUG_PERIPHERAL) NSLog(@"-- peripheral state changed: %@", peripheral.stateString);
    // Emit the state if stat is known.
    if (peripheral.state)
    {
        self.bluetoothWasTried = YES;
        [self emitBluetoothState];
    }
    // If powered on, start scanning
    if (peripheral.state == CBPeripheralManagerStatePoweredOn)
    {
        [self startAdvertising];
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (DEBUG_PERIPHERAL)
    {
        if (error)
            NSLog(@"error starting advertising: %@", [error localizedDescription]);
        else
            NSLog(@"did start advertising!");
    }
}


#pragma mark - iBeacon broadcasting

// Setup the beacon responsible for communicating the user's transponder ID
- (void)initIdentityBeacon:(NSString *)userID
{
    
    // Convert the userID into a major and minor value to transmit
    NSLog(@"Decomposing UUID %@",userID);
    uint16_t major, minor;
    esDecomposeIdToMajorMinor([userID intValue], &major, &minor);
    NSLog(@"Got major: %hu and minor:%hu",major,minor);
    
    CLBeaconRegion *identityBeaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IDENTITY_BEACON_UUID]
                                                                                   major:major
                                                                                   minor:minor
                                                                              identifier:[NSString stringWithFormat:@"Broadcast region %d",19]];
    self.identityBeaconData = [identityBeaconRegion peripheralDataWithMeasuredPower:nil];
    
}


// Below lie the functions for interacting with iBeacon
- (void)chirpBeacon
{
    NSLog(@"chirpBeacon called!");
    NSLog(@"Is stack running? %u", [self isRunning]);
    UIApplication *application = [UIApplication sharedApplication];
    if ([application applicationState] == UIApplicationStateActive) {
        
        // Don't do anything if you're already chirping
        if (self.currentlyChirping == YES) {
            if (DEBUG_BEACON) NSLog(@"Currently chirping, creation CANCELLED");
        } else{
            if (DEBUG_BEACON) NSLog(@"Attempting to create new beacon!");
            if (DEBUG_BEACON) NSLog(@"Current regions: %@",self.regions);
            // Build an array to sort
            NSMutableArray *fucker = [[NSMutableArray alloc] init];
            
            for (NSNumber *isInside in self.regions) {
                NSDictionary *bullshit = @{@"some": [[NSDate alloc] init],@"isInside":isInside};
                [fucker addObject:bullshit];
            }
            
            // Preticate - filter self.regions
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF.isInside == %@)", @NO];
            NSArray *availableNos = [fucker filteredArrayUsingPredicate:predicate];
            if (DEBUG_BEACON) NSLog(@"Available regions count: %lu",(unsigned long)[availableNos count]);
            if ([availableNos count])
            {
                NSInteger randomChoice = esRandomNumberIn(0, (int)[availableNos count]);
                id aNo = [availableNos objectAtIndex:randomChoice];
                
                NSUInteger chosenIndex = [availableNos indexOfObject:aNo];
                
                NSString *regionUUID = [self.regionUUIDS objectAtIndex:chosenIndex];
                
                if (DEBUG_BEACON) NSLog(@"Creating a new chirping beacon broadcast region in slot number %lu -> %@",(unsigned long)chosenIndex, regionUUID);
                self.chirpBeaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: regionUUID]
                                                                                 major:0
                                                                                 minor:0
                                                                            identifier:[NSString stringWithFormat:@"Broadcast region %d",chosenIndex]];
                self.chirpBeaconData = [self.chirpBeaconRegion peripheralDataWithMeasuredPower:nil];
                
                // Start chirping
                self.currentlyChirping = YES;
                
                // Stop chirping after 10 seconds
                [self performSelector:@selector(stopChirping) withObject:nil afterDelay:CHIRP_LENGTH];
                // This region should be off-limits for a bit
                [self disallowRegion:chosenIndex];
            } else
            {
                // Not chirping
                self.currentlyChirping = NO;
                int timeoutSeconds = 10;
                NSLog(@"Couldn't find an open region, trying again in %i seconds.",timeoutSeconds);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,  timeoutSeconds*1000* NSEC_PER_MSEC), dispatch_get_main_queue(),                ^{
                    // note - it's okay if this fires in the background
                    // this only sets the beacon data and the currentlyChirping flag, but it will be overridden by the flippingBreaker flag if the app is in the background
                    [self chirpBeacon];
                });
            }
        }
    } else{
        if (DEBUG_BEACON) NSLog(@"Application isn't in the foreground - not creating a beacon");
    }
    
}

- (void)stopChirping
{
    if (DEBUG_BEACON) NSLog(@"Stopping chirping!");
    self.currentlyChirping = NO;
    [self chirpBeacon];
}

- (void)disallowRegion:(NSUInteger)regionNumber
{
    if (DEBUG_BEACON) NSLog(@"Disallowing region %lu",(unsigned long)regionNumber);
    [self.regions replaceObjectAtIndex:regionNumber withObject:@YES];
    // In a while, re-allow the region
    [self performSelector:@selector(allowRegion:) withObject:[NSNumber numberWithInteger:regionNumber] afterDelay:30];
}

- (void)allowRegion:(NSNumber *)regionNumber
{
    if (DEBUG_BEACON) NSLog(@"Re-enabling region %@",regionNumber);
    [self.regions replaceObjectAtIndex:[regionNumber integerValue] withObject:@NO];
}

- (void)startFlipping
{
    // If you're in the foreground, start flipping the state
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
    {
        self.isFlipping = YES;
        self.broadcastMode = 0;
        self.flippingBreaker = NO;
        [self flipState];
    } else {
        // You're in the background, so just start broadcasting on BLE
        [self debugNote:@"Transponder is broadcasting in the background."];
        [self resetBluetooth];
    }
    
}

- (void)stopFlipping
{
    // Set the flag
    self.isFlipping = NO;
    // Stop flipState from continuing to flip
    self.flippingBreaker = YES;
    // Reset the bluetooth right now to broadcast BLE
//    if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE");
//    [self resetBluetooth];
    // Just in case, reset the bluetooth stack again in a few seconds (to miss any timeouts in the meantime)
    //    [self performSelector:@selector(resetBluetooth) withObject:nil afterDelay:1.5];
    
}

- (void)flipState
{

    // There are three states:
    // State 0: Broadcasting using normal BLE
    // State 1: Broadcasting as an iBeacon on a wakeup region (0-18)
    // State 2: Broadcasting as an iBeacon as this device on Region 19
    
    // ^ optional, only available is self.discoveryBeacon == @YES
    
    if (!self.flippingBreaker) {
        // Increment the broadcast mode
        self.broadcastMode++;
        
//        // Reset it if necessary
//        if (self.broadcastMode > 2) {
//            self.broadcastMode = 0;
//        }
//        
////        self.broadcastMode = 1;
//        
//        // Check the broadcast mode
//        switch (self.broadcastMode) {
//            case 0:
//                // Start broadcasting using normal bluetooth low energy
//                if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE");
//                [self resetBluetooth];
//                break;
//            case 1:
//                // Is this flag set?
//                if (self.currentlyChirping == YES) {
//                    // Start broadcasting as a wakeup region
//                    if (DEBUG_BEACON) NSLog(@"-- broadcasting as chirp iBeacon");
//                    [self startBeacon:self.chirpBeaconData];
//                } else{
//                    // Broadcast as normal BLE
//                    if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE (no chirp fallback)");
//                    [self resetBluetooth];
//                }
//                // Start broadcasting on a wakeup region
////                [self performSelector:@selector(flipState) withObject:nil afterDelay:1.0];
//                break;
//            case 2:
//                // Start broadcasting as an iBeacon on identity beacon
//                if (DEBUG_BEACON) NSLog(@"-- broadcasting as identity iBeacon");
//                [self startBeacon:self.identityBeaconData];
////                [self performSelector:@selector(flipState) withObject:nil afterDelay:5.0];
//                break;
//            default:
//                break;
//        }
        
        // Reset it if necessary
        if (self.broadcastMode > 1) {
            self.broadcastMode = 0;
        }
        
        //        self.broadcastMode = 1;
        
        // Check the broadcast mode
        switch (self.broadcastMode) {
            case 0:
                // Start broadcasting as a wakeup region
                if (DEBUG_BEACON) NSLog(@"-- broadcasting as chirp iBeacon");
                [self startBeacon:self.chirpBeaconData];
                // Quickly switch to identity
                [self performSelector:@selector(flipState) withObject:nil afterDelay:2.0];
                break;
            case 1:
                // Start broadcasting as an iBeacon on identity beacon
                if (DEBUG_BEACON) NSLog(@"-- broadcasting as identity iBeacon");
                [self startBeacon:self.identityBeaconData];
                // Do this cycle again after 10 seconds
                [self performSelector:@selector(flipState) withObject:nil afterDelay:30.0];
                break;
            default:
                break;
        }
        
        
    }
    
}

- (void)resetBluetooth
{
    // Stop what you're doing and advertise with bluetooth
    [self.peripheralManager stopAdvertising];
    [self.peripheralManager startAdvertising:self.bluetoothAdvertisingData];
}

// Start broadcasting as an iBeacon. Works with either the identity or wakeup beacon data
- (void)startBeacon:(NSDictionary *)beaconData
{
    // Stop what you're doing and advertise as a beacon
    [self.peripheralManager stopAdvertising];
    // Broadcast
    [self.peripheralManager performSelector:@selector(startAdvertising:) withObject:beaconData afterDelay:0.5];
}


# pragma mark - iBeacon discovery
// K this shit gets crazy so stay with me. We're going to listen for "chirps" (broadcasts under 10 seconds for the purpose of wakeup) on regions 0-18. Region 19 is special. Region 19 is where we will actually range beacons. Therefore a phone can chirp on region 10, and ranging will start on region 19.
- (void)setupBeaconRegions
{
    NSLog(@"Setting up beacon regions...");
    // Make the location manager
    self.locationManager = [[CLLocationManager alloc] init];
    // Set the delegate
    self.locationManager.delegate = self;
    
    //    BOOL what = [CLLocationManager isMonitoringAvailableForClass:[CLBeacon class]];
    //    int [CLLocationManager] auth
    // Init the region tracker
    self.regions = [[NSMutableArray alloc] init];
    
    // Log the regions already monitored
    for (CLRegion *monitored in [self.locationManager monitoredRegions]){
        NSLog(@"Already monitoring region: %@", monitored);
        //        [self.locationManager stopMonitoringForRegion:monitored];
    }
    
    // Regions 0-18 are available for wakeup chirps
    for (int major=0; major< MAX_BEACON; major++) {
        NSString *regionUUID = [self.regionUUIDS objectAtIndex:major];
        if (DEBUG_BEACON) NSLog(@"Starting to monitor for region %@",regionUUID);
        // Start outside the region
        [self.regions addObject:@NO];
        // Create a region with this minor
        CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: regionUUID]
                                                                    identifier:[NSString stringWithFormat:@"Listen region %@",regionUUID]];
        // Wake up the app when you enter this region
        //        region.notifyEntryStateOnDisplay = YES;
        region.notifyOnEntry = YES;
        region.notifyOnExit = YES;
        // Start monitoring via location manager
        [self.locationManager startMonitoringForRegion:region];
        // OPTIONAL - if we need to initialize this region with an inside/outside state, do it here
        [self.locationManager requestStateForRegion:region];
    }
    
    
    // Region 19 is available for ranging - totally separate
    // This might look like duplicate code, but it's way easier to understand if this gets set up as a separate region
    if (DEBUG_BEACON) NSLog(@"Setting up the mystical region %@",IDENTITY_BEACON_UUID);
    self.rangingRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IDENTITY_BEACON_UUID]
                                                            identifier:[NSString stringWithFormat:@"Identity region %@",IDENTITY_BEACON_UUID]];
    //    self.rangingRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
    //                                                            identifier:[NSString stringWithFormat:@"Minor mod region:%d",19]];
    // Why not also wake up when we enter this region
    //    self.rangingRegion.notifyEntryStateOnDisplay = YES;
    self.rangingRegion.notifyOnEntry = YES;
    self.rangingRegion.notifyOnExit = YES;
    // Start monitoring via location manager
    [self.locationManager startMonitoringForRegion:self.rangingRegion];
    // OPTIONAL - if we need to initialize this region with an inside/outside state, do it here
    [self.locationManager requestStateForRegion:self.rangingRegion];
    // Start ranging for beacons in this region
    [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
    
    
}

- (void)stopRanging
{
    [self.locationManager stopRangingBeaconsInRegion:self.rangingRegion];
}

#pragma mark - CLLocationManagerDelegate
//- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
//{
//    NSLog(@"AHH DID EENTER REGION");
//}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    NSLog(@"status 2 ?= %d", status);
    // Emit that shit, unless underetmined state.
    if (status == kCLAuthorizationStatusNotDetermined)
    {
        return;
    }
    self.coreLocationWasTried = YES;
    [self emitBluetoothState];
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLBeaconRegion *)region
{
    // What region?
    NSUUID *uuidVal = [region proximityUUID];
    NSString *uuid = [uuidVal UUIDString];
    if(DEBUG_BEACON) NSLog(@"Got region event with UUID: %@",uuid);
    NSUInteger indexOfThisRegion = [self.regionUUIDS indexOfObject:uuid];
    //    NSLog(@"Got state %ld for region %lu", state, (unsigned long)indexOfThisRegion);
    //    NSLog(@"Got state %li for region %@ : %@",state,minor,region);
    
    // Start ranging
    [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
    
    switch (state) {
        case CLRegionStateInside:
            // Update the beacon regions dictionary if it's not Region 19
            if (![uuid  isEqual: IDENTITY_BEACON_UUID]) {
                if (indexOfThisRegion != NSNotFound){
                    [self.regions replaceObjectAtIndex:indexOfThisRegion withObject:@YES];
                }
            }
            // Regardless, start ranging on Region 19
            [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
            // Kill any existing timeouts
//            if (self.rangingTimeout) {
//                [self.rangingTimeout invalidate];
//            }
//            // If we're in the background, don't do this forever
//            if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
//                // Make a new timer
//                self.rangingTimeout = [NSTimer timerWithTimeInterval:BEACON_TIMEOUT target:self selector:@selector(stopRanging) userInfo:nil repeats:NO];
//                // Actually start the timer
//                [[NSRunLoop mainRunLoop] addTimer:self.rangingTimeout forMode:NSDefaultRunLoopMode];
//            }
            
            // Send a local notification to tell the user we discovered a device
            [self sendAnonymousNotification];
            
            if (DEBUG_BEACON){
                NSLog(@"--- Entered region: %@", region);
                [self debugNote:[NSString stringWithFormat:@"Entered region %lu",(unsigned long)indexOfThisRegion]];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateOutside:
            if (![uuid  isEqual: IDENTITY_BEACON_UUID]) {
                if (indexOfThisRegion != NSNotFound){
                    [self.regions replaceObjectAtIndex:indexOfThisRegion withObject:@NO];
                }
            }
            if (DEBUG_BEACON){
                NSLog(@"--- Exited region: %@", region);
                [self debugNote:[NSString stringWithFormat:@"Exited region %lu",(unsigned long)indexOfThisRegion]];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateUnknown:
            if (DEBUG_BEACON) NSLog(@"Region %@ in unknown state - doing nothing...",uuid);
            break;
        default:
            NSLog(@"This is never supposed to happen.");
            break;
    }
    
    // Doing this for some reason scans forever...
    //    [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
}

-(void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region
{
    if ([beacons count] != 0){
        if (DEBUG_BEACON) NSLog(@"Ranged beacons from identity region!");
        if (DEBUG_BEACON) NSLog(@"%@",beacons);
    }
    
    if (DEBUG_BEACON) NSLog(@"--- Found %lu beacons in range.", (unsigned long)[beacons count]);
    
    for (CLBeacon *beacon in beacons) {
        //        NSString *userID = [NSString stringWithFormat:@"%@",beacon.minor];
        
        uint32_t recomposed;
        esRecomposeMajorMinorToId([beacon.major intValue], [beacon.minor intValue], &recomposed);
        //        NSLog(@"Recomposed major: %@ and minor:%@   ->   %d",beacon.major,beacon.minor,recomposed);
        
        NSString *userID = [NSString stringWithFormat:@"%u",recomposed];
        
        // Send a non-anonymous notification (or try to, at least)
        [self sendNonanonymousNotification:userID];
        
//        if (DEBUG_BEACON) NSLog(@"%@ addUser %@ <locationManager:didRangeBeacons:inRegion:>", [FCUser owner].id, userID);
        [self sightedBroadcaster:userID withRSSI:[NSNumber numberWithInteger:beacon.rssi]];
//        [self addUser:userID];
    }
}

- (ESTransponderStackState)isRunning
{
    if (self.coreLocationWasTried && self.bluetoothWasTried)
    {
        
        if (self.peripheralManager.state == CBPeripheralManagerStatePoweredOn &&
            self.centralManager.state == CBPeripheralManagerStatePoweredOn &&
            [CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized)
        {
            return ESTransponderStackStateActive;
        } else
        {
            return ESTransponderStackStateDisabled;
        }
    }
    return ESTransponderStackStateUnknown;
}

- (void)emitBluetoothState
{
    if (self.coreLocationWasTried && self.bluetoothWasTried)
    {
        BOOL peripheralManagerStateSuccess = (self.peripheralManager.state == CBPeripheralManagerStatePoweredOn);
        BOOL centraManagerStateSuccess = (self.centralManager.state == CBPeripheralManagerStatePoweredOn);
        BOOL locationManagerStateSuccess = ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized);
        
        NSLog(@"peripheralManagerStateSuccess-%d centralManagerStateSuccess-%d locationManagerStateSuccess-%d", peripheralManagerStateSuccess, centraManagerStateSuccess, locationManagerStateSuccess);
        
        if (self.peripheralManager.state == CBPeripheralManagerStatePoweredOn &&
            self.centralManager.state == CBPeripheralManagerStatePoweredOn &&
            [CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized)
        {
            
            if (reportStackFailureTimer)
            {
                [reportStackFailureTimer invalidate];
                reportStackFailureTimer = nil;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:TransponderEnabled object:nil];
        } else
        {
            if (!reportStackFailureTimer)
            {
                reportStackFailureTimer = [NSTimer timerWithTimeInterval:REPORT_FAILURE_IN_STACK_TIMEOUT target:self selector:@selector(reportStackFailureTimerAction:) userInfo:nil repeats:NO];
                [[NSRunLoop mainRunLoop] addTimer:reportStackFailureTimer forMode:NSDefaultRunLoopMode];
            }
        }
    }
}

-(void)reportStackFailureTimerAction:(NSTimer*)theTimer
{
    [reportStackFailureTimer invalidate];
    reportStackFailureTimer = nil;
    //emit the failure notification
    [[NSNotificationCenter defaultCenter] postNotificationName:TransponderDisabled object:nil];
}

-(CLLocation*)getLocation
{
    return self.locationManager.location;
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error
{
    NSLog(@"Region monitoring failed for region: %@", region);
    NSLog(@"Region monitoring failed with error: %@", [error localizedDescription]);
    
    // If we haven't already sent an error, send one
    if (SHOW_DEBUG_NOTIFICATIONS && !self.hasSentErrorNote) {
        [self debugNote:@"iBeacons have broken down"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"ERROR - %@",error);
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region
{
    NSLog(@"Started monitoring for region: %@",region);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    NSLog(@"Did update location significantly!");
    self.okayToSendAnonymousNotification = YES;
}

- (void)sendAnonymousNotification
{
    if (self.okayToSendAnonymousNotification){
        NSLog(@"%@ YES", NSStringFromSelector(_cmd));
        [self sendDiscoverNotification];
        self.okayToSendAnonymousNotification = NO;
    } else
    {
        NSLog(@"%@ NO", NSStringFromSelector(_cmd));
//        [self debugNote:@"NOT sending anon note - already sent"];
    }
}

- (void)sendNonanonymousNotification:(NSString *)userID
{
    // Only send if we haven't seen this user before
    if ([self.seen indexOfObject:userID] != NSNotFound) {
        // Attempt to send the notification
        [self sendDiscoverNotification];
    } else {
//        [self debugNote:@"NOT sending anon note - user already seen"];
    }
}

# pragma mark - local notifications
- (void)sendDiscoverNotification

{
    // The app icon badge listens to these events
    if ([[self.earshotUsers allKeys] count] == 0){
        // Badge the number of bluetooth users
//        [[NSNotificationCenter defaultCenter] postNotificationName:kTransponderEventCountUpdated object:self userInfo:@{@"count":[NSNumber numberWithLong:[[self.bluetoothUsers allKeys] count]]}];
        //        [[NSNotificationCenter defaultCenter] postNotificationName:kTransponderEventCountUpdated object:self userInfo:@{@"count":@1}];
    } else {
        // Badge the number of users tracked via firebase
//        [[NSNotificationCenter defaultCenter] postNotificationName:kTransponderEventCountUpdated object:self userInfo:@{@"count":[NSNumber numberWithLong:[[self.earshotUsers allKeys] count]]}];
    }
    // Only do this if the app is in the background
    //    NSLog(@"Current app state is %ld",[[UIApplication sharedApplication] applicationState]);
    UIApplication *app = [UIApplication sharedApplication];
    if ([app applicationState] == UIApplicationStateBackground)
    {
        // If there aren't any existing discover notifications
        NSArray *notificationArray = [app scheduledLocalNotifications];
        if ([notificationArray count] == 0)
        {
            // If it's been more than 20 minutes since the last notification OR app open
            NSDate *currentDate = [NSDate date];
            NSTimeInterval howLong = [currentDate timeIntervalSinceDate:self.lastNotificationEvent];
            if (isnan(howLong) || howLong > NOTIFICATION_TIMEOUT) {
                NSLog(@"Sending a local discover notification!");
                // Cancel all of the existing notifications
//                [app cancelAllLocalNotifications];
                // Add a new notification
//                UILocalNotification *notice = [[UILocalNotification alloc] init];
//                notice.alertBody = [NSString stringWithFormat:@"Shortwave users nearby!"];
//                notice.alertAction = @"Converse";
//                [app scheduleLocalNotification:notice];
                [[NSNotificationCenter defaultCenter] postNotificationName:TransponderSuggestsDiscoveryNotification object:nil];
                // Update the date we use for the notification timeout
                self.lastNotificationEvent = [NSDate date];
                // Track this via mixpanel
//                [self.mixpanel track:@"Notified of user nearby" properties:@{}];
                // Suggest that the app notify a user
                
                
            } else{
                NSLog(@"It has only been %f seconds of the %f second notification timeout - ignoring notification call.", howLong, NOTIFICATION_TIMEOUT);
//                [self debugNote:@"NOT sending disc note - timeout too short"];
            }
        } else {
            NSLog(@"There is already an existing discover notification - ignoring notification call");
        }
        
    } else
    {
        NSLog(@"App is not in the background - ignoring notication call.");
    }
}

# pragma mark - transponder events
- (void)sendUserDiscoverEvent:(NSString *)uuid
{
    NSDictionary *userInfo = @{@"uuid": uuid};
    [[NSNotificationCenter defaultCenter] postNotificationName:TransponderUserDiscovered object:nil userInfo:userInfo];
}

- (void)sendAnonymousUserDiscoverEvent
{
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TransponderAnonymousUserDiscovered object:nil];
}

# pragma mark - post queue
- (void)sightedBroadcaster:(NSString *)broadcasterID withRSSI:(NSNumber *)rssi
{
    // Build the sighting object and add the timestamp
    NSDictionary *sighting = @{@"sighted": broadcasterID,
                               @"rssi": rssi,
                               @"timestamp": [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]
                               };
//    NSLog(@"Adding sighting: %@", sighting);
    
    NSNumber *timestamp = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]];
    
    //added to disk-stored push/post queue
    [sightingPushQueue addSightingWithID:broadcasterID withRSSI:rssi andTimestamp:timestamp];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



@end
