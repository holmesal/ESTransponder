//
//  ESTransponder.m
//  Earshot
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import "ESTransponder.h"
#import <Firebase/Firebase.h>

// Extensions
#import "CBCentralManager+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBUUID+Ext.h"
#import "Math.h"

#define DEBUG_CENTRAL NO
#define DEBUG_PERIPHERAL NO
#define DEBUG_BEACON YES
#define DEBUG_USERS NO

#define IS_RUNNING_ON_SIMULATOR NO

#define MAX_BEACON 19
#define TIMEOUT 10.0 //For users
#define BEACON_TIMEOUT 10.0 //For beacon ranging in the background

@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate>
// Bluetooth / main class stuff
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSDictionary *bluetoothAdvertisingData;
@property (strong, nonatomic) NSMutableDictionary *bluetoothUsers;

// Beacon broadcasting
@property NSInteger flipCount;
//@property BOOL isAdvertisingAsBeacon;
@property BOOL currentlyChirping;
@property BOOL flippingBreaker;
@property (strong, nonatomic) CLBeaconRegion *chirpBeaconRegion;
@property (strong, nonatomic) NSDictionary *chirpBeaconData;
@property (strong, nonatomic) NSDictionary *identityBeaconData;

// Beacon monitoring
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) NSMutableArray *regions;
@property (strong, nonatomic) CLBeaconRegion *rangingRegion;
@property (strong, nonatomic) NSTimer *rangingTimeout;

// Firebase-synced users array
@property (strong, nonatomic) Firebase *rootRef;
@property (strong, nonatomic) Firebase *earshotUsersRef;
//@property (strong, nonatomic) NSMutableDictionary *earshotUsers;

// Oscillator
@property NSInteger broadcastMode;

@end

@implementation ESTransponder
@synthesize earshotID;
@synthesize peripheralManagerIsRunning;

- (id)initWithEarshotID:(NSString *)userID andFirebaseRootURL:(NSString *)firebaseURL
{
    if ((self = [super init])) {
        self.earshotID = userID;
        self.identifier = [CBUUID UUIDWithString:IDENTIFIER_STRING];
        self.bluetoothUsers = [[NSMutableDictionary alloc] init];
        // Setup the firebase
        [self initFirebase:firebaseURL];
        // Create the identity iBeacon
        [self initIdentityBeacon:userID];
        // Start off NOT flipping between identity beacon / chirping beacon
        self.currentlyChirping = NO;
        // Start off with a broadcast mode of 0
        self.broadcastMode = 0;
        // Start flipping between the identity beacon and BLE
        [self startFlipping];
        // Chirp another beacona  few times to wake up other users
        [self chirpBeacon];
        // Start a repeating timer to prune the in-range users, every 10 seconds
        [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(pruneUsers) userInfo:nil repeats:YES];
        // Listen for chirpBeacon events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chirpBeacon) name:@"chirpBeacon" object:nil];
        // Listen for app sleep events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
        // Listen for app wakeup events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterBackground) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}

- (void)pruneUsers
{
    if (DEBUG_USERS) NSLog(@"Pruning users!");
    
    // WHATTIMEISITRIGHTNOW.COM
    NSDate *now = [[NSDate alloc] init];
    // Check every user
    for(NSString *userBeaconKey in [self.bluetoothUsers.allKeys copy])
    {
        NSMutableDictionary *userBeacon = [self.bluetoothUsers objectForKey:userBeaconKey];
        // How long ago was this?
        float lastSeen = [now timeIntervalSinceDate:[userBeacon objectForKey:@"lastSeen"]];
        if (DEBUG_USERS) NSLog(@"time interval for %@ -> %f",[userBeacon objectForKey:@"earshotID"],lastSeen);
        // If it's longer than 20 seconds, they're probs gone
        if (lastSeen > TIMEOUT) {
            if (DEBUG_USERS) NSLog(@"Removing user: %@",userBeacon);
            // Remove from earshotUsers, if it's actually in there
            if ([userBeacon objectForKey:@"earshotID"] != [NSNull null]) {
                [self removeUser:[userBeacon objectForKey:@"earshotID"]];
            }
            // Remove from bluetooth users
            [self.bluetoothUsers removeObjectForKey:userBeaconKey];
        } else {
            if (DEBUG_USERS) NSLog(@"Not removing user: %@",userBeacon);
        }
    }
    
}

- (void)initFirebase:(NSString *)baseURL
{
    self.earshotUsers = [[NSMutableDictionary alloc] init];
    self.rootRef = [[Firebase alloc] initWithUrl:baseURL];
    self.earshotUsersRef = [[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:self.earshotID] childByAppendingPath:@"tracking"];
    [self.earshotUsersRef observeEventType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {
        // Update the locally-stored earshotUsers array
        NSLog(@"Got data from firebase");
        NSLog(@"%@",snapshot.value);
        if (snapshot.value != [NSNull null]){
            self.earshotUsers = [NSMutableDictionary dictionaryWithDictionary:snapshot.value];
            // Filter the users based on timeout
            //            [self filterFirebaseUsers];
        }
    }];
}

- (void)filterFirebaseUsers
{
    // Store the current time
    NSDate *currentDate = [NSDate date];
    for (NSString *userKey in self.earshotUsers) {
        // If the timeout is too old, clear it out
        NSNumber *timestampNumber = [self.earshotUsers objectForKey:userKey];
        long timestamp = [timestampNumber longValue];
        
        NSDate *beforeDate = [[NSDate alloc] initWithTimeIntervalSince1970:timestamp];
        
        NSTimeInterval interval = [currentDate timeIntervalSinceDate:beforeDate];
        
        NSLog(@"Long filter timeout for user %@ --> %f",userKey,interval);
        
        if (interval > TIMEOUT * 10.0) {
            NSLog(@"REMOVING USER %@ - has been too long",userKey);
            // Remove the user
            [self removeUser:userKey];
        }
    }
}

// Takes in a bluetooth user and adds it to earshotUsers
- (void)addUser:(NSString *)userID
{
    NSLog(@"Adding user to firebase: %@",userID);
    // Add the user for yourself
    uint rounded = [self roundTime:[[NSDate date] timeIntervalSince1970]];
    NSLog(@"Rounded time is %d",rounded);
//    NSTimeInterval secs = [[[NSDate alloc] init] timeIntervalSince1970];
//    NSDictionary *val = @{@"lastSeen": [[NSString alloc] initWithFormat:@"%f",secs]};
//    NSDictionary *trackingData = @{@"lastSeen": [[NSString alloc] initWithFormat:@"%u",rounded]};
    [[self.earshotUsersRef childByAppendingPath:userID] setValue:[[NSNumber alloc] initWithInt:rounded]];
    // Add yourself for the user
    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.earshotID] setValue:[[NSNumber alloc] initWithInt:rounded]];
}

- (uint)roundTime:(NSTimeInterval)time
{
    // Round to the nearest 5 seconds
    //    NSLog(@"time = %f", time);
    double rounded = TIMEOUT * floor((time/TIMEOUT)+0.5);
    return rounded;
}

- (void)removeUser:(NSString *)userID
{
#warning not sure this is the right way to handle removing users...
#warning - add feature to not remove this user if it exists elsewhere in the bluetooth array
    // Remove the user for yourself
    [[self.earshotUsersRef childByAppendingPath:userID] removeValue];
    // Remove yourself for the user
    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.earshotID] removeValue];
}



# pragma mark - FOREGROUND vs BACKGROUND modes
- (void)appWillEnterForeground
{
    NSLog(@"Transponder -- App is entering foreground");
    // Start ranging beacons in Region 19
    [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
    // Start flipping between an iBeacon and a BLE peripheral
    [self startFlipping];
    // Chirp the discovery iBeacon for a few seconds
    [self chirpBeacon];
}

- (void)appWillEnterBackground
{
    NSLog(@"Transponder -- App is entering background");
    // Stop chirping as a beacon
    [self stopChirping];
    // Start advertising only as a BLE peripheral
    [self stopFlipping];
    // Stop ranging beacons
    [self stopRanging];
}

# pragma mark - push notifications
- (void)wakeup
{
    // Only do this if the app is in the background
    //    NSLog(@"Current app state is %ld",[[UIApplication sharedApplication] applicationState]);
    UIApplication *app = [UIApplication sharedApplication];
    if ([app applicationState] == UIApplicationStateBackground) {
        NSLog(@"App is in the background!");
        // If there aren't any user notifications, add a new earshot notification
        NSArray *notificationArray = [app scheduledLocalNotifications];
        NSLog(@"notificationArray count is %@", [notificationArray count]);
        //        if ([notificationArray count] != 0) {
        //            // Delete all the existing notifications
        //            NSLog(@"Deleting local notifications");
        //            [app cancelAllLocalNotifications];
        ////            for (UILocalNotification *toDelete in notificationArray) {
        ////                app cancelAllLocalNotifications
        ////            }
        //        }
        //        [app cancelAllLocalNotifications];
        // Add a new notifications
        UILocalNotification *notice = [[UILocalNotification alloc] init];
        notice.alertBody = [NSString stringWithFormat:@"Earshot users nearby."];
        notice.alertAction = @"Converse";
        [app scheduleLocalNotification:notice];
    } else
    {
        NSLog(@"App is not in the background - ignoring wakeup call.");
    }
    // If there aren't any user notifications, add a new earshot notification
    // TODO - check if there are already notifications
    // If there are currently notifications, add this one and then delete it right away
}

# pragma mark - core bluetooth

- (void)startDetecting
{
    // Setup beacon monitoring for regions
    [self setupBeaconRegions];
    // Listen for bluetooth LE
    [self startDetectingTransponders];
}

- (void)startBroadcasting
{
    
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
    
    self.bluetoothAdvertisingData = @{CBAdvertisementDataServiceUUIDsKey:@[self.identifier], CBAdvertisementDataLocalNameKey:self.earshotID};
    
    // Start advertising over BLE
    [self.peripheralManager startAdvertising:self.bluetoothAdvertisingData];
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
                                                                                         @"earshotID": [NSNull null]}];
        // Insert
        [self.bluetoothUsers setObject:newUser forKey:[peripheral.identifier UUIDString]];
        
        // Alias
        existingUser = newUser;
        
        // Send the new (anonymous) user notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"newUserDiscovered" object:self userInfo:@{@"user":existingUser}];
        
        // Chirp the beacon!
//        [self chirpBeacon];
    } else{
        // Update the time last seen
        [existingUser setObject:[[NSDate alloc] init] forKey:@"lastSeen"];
    }
    
    // Update local name if included in advertisement
    NSString *localName = [advertisementData valueForKey:@"kCBAdvDataLocalName"];
    if (localName){
        [existingUser setValue:localName forKey:@"earshotID"];
        // Add to earshot users
# warning - this is turned off! turn it back on ya fool!
//        [self addUser:localName];
    }
    
    if (DEBUG_CENTRAL) NSLog(@"%@",self.bluetoothUsers);
    
    // Notify peeps that an earshot user was discovered
    [[NSNotificationCenter defaultCenter] postNotificationName:@"earshotDiscover"
                                                        object:self
                                                      userInfo:@{@"user":existingUser,
                                                                 @"identifiedUsers":self.earshotUsers,
                                                                 @"bluetoothUsers":self.bluetoothUsers}];
    
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (DEBUG_CENTRAL) NSLog(@"-- central state changed: %@", self.centralManager.stateString);
    
    /*CBPeripheralManagerStateUnknown = 0,
     CBPeripheralManagerStateResetting,
     CBPeripheralManagerStateUnsupported,
     CBPeripheralManagerStateUnauthorized,
     CBPeripheralManagerStatePoweredOff,
     CBPeripheralManagerStatePoweredOn
     */
    if (DEBUG_CENTRAL) NSLog(@"\n");
    switch (central.state) {
        case CBPeripheralManagerStateUnknown:
        {
            if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStateUnknown");
        }
            break;
        case CBPeripheralManagerStateResetting:
        {
            if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStateResetting");
        }
            break;
        case CBPeripheralManagerStateUnsupported:
        {
            //just for when I am running on simulator,
            if (!IS_RUNNING_ON_SIMULATOR)
            {
                //unsuported state means the device cannot do bluetooth low energy
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Oh noes" message:@"The platform doesn't support the Bluetooth low energy peripheral/server role." delegate:nil cancelButtonTitle:@"Dang!" otherButtonTitles:nil];
                [alert show];
                self.peripheralManagerIsRunning = NO;
                if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStateUnsupported");
            } else
            {
                if (DEBUG_CENTRAL) NSLog(@"FAKE CBPeripheralManagerStateUnauthorized");
                self.peripheralManagerIsRunning = NO;
                
                [self blueToothStackNeedsUserToActivateMessage];
            }
        }
            break;
        case CBPeripheralManagerStateUnauthorized:
        {
            if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStateUnauthorized");
            self.peripheralManagerIsRunning = NO;
            
            [self blueToothStackNeedsUserToActivateMessage];
            
        }
            break;
        case CBPeripheralManagerStatePoweredOff:
        {
            if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStatePoweredOff");
            self.peripheralManagerIsRunning = NO;
            
            [self blueToothStackNeedsUserToActivateMessage];
            
        }
            break;
        case CBPeripheralManagerStatePoweredOn:
        {
            if (DEBUG_CENTRAL) NSLog(@"CBPeripheralManagerStatePoweredOn");
            //            self.peripheralManagerIsRunning = YES;
            [self startScanning];
        }
            break;
    }
    if (DEBUG_CENTRAL) NSLog(@"\n");
    
}

#pragma mark - CBPeripheralManagerDelegate
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    if (DEBUG_PERIPHERAL) NSLog(@"-- peripheral state changed: %@", peripheral.stateString);
    
    if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
        [self startAdvertising];
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (DEBUG_PERIPHERAL) {
        if (error)
            NSLog(@"error starting advertising: %@", [error localizedDescription]);
        else
            NSLog(@"did start advertising!");
    }
}


#pragma mark - iBeacon broadcasting

// Setup the beacon responsible for communicating the user's earshot ID
- (void)initIdentityBeacon:(NSString *)userID
{
    CLBeaconRegion *identityBeaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                         major:19
                                                                         minor:[userID intValue]
                                                                    identifier:[NSString stringWithFormat:@"Broadcast region %d",19]];
    self.identityBeaconData = [identityBeaconRegion peripheralDataWithMeasuredPower:nil];
    
}


// Below lie the functions for interacting with iBeacon
- (void)chirpBeacon
{
    
    if (DEBUG_BEACON) NSLog(@"Attempting to create new beacon!");

    // Don't do anything if you're already chirping
    if (self.currentlyChirping == YES) {
        if (DEBUG_BEACON) NSLog(@"Currently chirping, creation CANCELLED");
    } else{
        // Build an array to sort
        NSMutableArray *fucker = [[NSMutableArray alloc] init];

        for (NSNumber *isInside in self.regions) {
            NSDictionary *bullshit = @{@"some": [[NSDate alloc] init],@"isInside":isInside};
            [fucker addObject:bullshit];
        }

        // Preticate - filter self.regions
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF.isInside == %@)", @NO];
        NSArray *availableNos = [fucker filteredArrayUsingPredicate:predicate];
        if ([availableNos count])
        {
            NSInteger randomChoice = esRandomNumberIn(0, (int)[availableNos count]);
            id aNo = [availableNos objectAtIndex:randomChoice];

            int major = [availableNos indexOfObject:aNo];

            if (DEBUG_BEACON) NSLog(@"Creating a new chirping beacon broadcast region in slot number %i",major);
            self.chirpBeaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                                 major:major
                                                                                 minor:0
                                                                            identifier:[NSString stringWithFormat:@"Broadcast region %i",major]];
            self.chirpBeaconData = [self.chirpBeaconRegion peripheralDataWithMeasuredPower:nil];

            // Start chirping
            self.currentlyChirping = YES;
            // Stop chirping after 10 seconds
            [self performSelector:@selector(stopChirping) withObject:nil afterDelay:10.0];
        } else
        {
            int timeoutSeconds = 10;
            NSLog(@"Couldn't find an open region, trying again in %i seconds.",timeoutSeconds);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,  timeoutSeconds*1000* NSEC_PER_MSEC), dispatch_get_main_queue(),                ^{
                // note - it's okay if this fires in the background
                // this only sets the beacon data and the currentlyChirping flag, but it will be overridden by the flippingBreaker flag if the app is in the background
                [self chirpBeacon];
            });
        }
    }
    
    
}

- (void)stopChirping
{
    if (DEBUG_BEACON) NSLog(@"Stopping chirping!");
    self.currentlyChirping = NO;
}

- (void)startFlipping
{
    self.broadcastMode = 0;
    self.flippingBreaker = NO;
    [self flipState];
}

- (void)stopFlipping
{
    // Stop flipState from continuing to flip
    self.flippingBreaker = YES;
    // Reset the bluetooth right now to broadcast BLE
    if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE");
    [self resetBluetooth];
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
        
        // Reset it if necessary
        if (self.broadcastMode > 2) {
            self.broadcastMode = 0;
        }
        
        // Check the broadcast mode
        switch (self.broadcastMode) {
            case 0:
                // Start broadcasting using normal bluetooth low energy
                if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE");
                [self resetBluetooth];
                break;
            case 1:
                // Is this flag set?
                if (self.currentlyChirping == YES) {
                    // Start broadcasting as a wakeup region
                    if (DEBUG_BEACON) NSLog(@"-- broadcasting as chirp iBeacon");
                    [self startBeacon:self.chirpBeaconData];
                } else{
                    // Broadcast as normal BLE
                    if (DEBUG_BEACON) NSLog(@"-- broadcasting as BLE (no chirp fallback)");
                    [self resetBluetooth];
                }
                // Start broadcasting on a wakeup region
                break;
            case 2:
                // Start broadcasting as an iBeacon on region 19
                if (DEBUG_BEACON) NSLog(@"-- broadcasting as identity iBeacon");
                [self startBeacon:self.identityBeaconData];
                break;
            default:
                break;
        }
        
        // Do this again after a while
        [self performSelector:@selector(flipState) withObject:nil afterDelay:1.0];
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
    [self.peripheralManager startAdvertising:beaconData];
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
    
    BOOL what = [CLLocationManager isMonitoringAvailableForClass:[CLBeacon class]];
//    int [CLLocationManager] auth
    // Init the region tracker
    self.regions = [[NSMutableArray alloc] init];
    
    for (CLRegion *monitored in [self.locationManager monitoredRegions]){
        [self.locationManager stopMonitoringForRegion:monitored];
    }
    
    // Regions 0-18 are available for wakeup chirps
    for (int major=0; major< MAX_BEACON; major++) {
        if (DEBUG_BEACON) NSLog(@"Starting to monitor for region %i",major);
        // Start outside the region
        [self.regions addObject:@NO];
        // Create a region with this minor
        CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                         major:major
                                                                    identifier:[NSString stringWithFormat:@"Listen region major:%i",major]];
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
    if (DEBUG_BEACON) NSLog(@"Setting up the mystical region 19");
    self.rangingRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                 major:19
                                                            identifier:[NSString stringWithFormat:@"Minor mod region:%d",19]];
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
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    NSLog(@"AHH DID EENTER REGION");
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    // What region?
    NSNumber *major = [region valueForKey:@"major"];
    //    NSLog(@"Got state %li for region %@ : %@",state,minor,region);
    switch (state) {
        case CLRegionStateInside:
            // Update the beacon regions dictionary if it's not Region 19
            if (![major  isEqual: @19]) {
                [self.regions replaceObjectAtIndex:[major intValue] withObject:@YES];
            }
            // Regardless, start ranging on Region 19
            [self.locationManager startRangingBeaconsInRegion:self.rangingRegion];
            // Kill any existing timeouts
            if (self.rangingTimeout) {
                [self.rangingTimeout invalidate];
            }
            // If we're in the background, don't do this forever
            if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
                // Make a new timer
                self.rangingTimeout = [NSTimer timerWithTimeInterval:BEACON_TIMEOUT target:self selector:@selector(stopRanging) userInfo:nil repeats:NO];
                // Actually start the timer
                [[NSRunLoop mainRunLoop] addTimer:self.rangingTimeout forMode:NSDefaultRunLoopMode];
            }
            
            if (DEBUG_BEACON){
                NSLog(@"--- Entered region: %@", region);
//                UILocalNotification *notice = [[UILocalNotification alloc] init];
//                notice.alertBody = [NSString stringWithFormat:@"Entered region %@",major];
//                notice.alertAction = @"Open";
//                [[UIApplication sharedApplication] scheduleLocalNotification:notice];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateOutside:
            if (![major  isEqual: @19]) {
                [self.regions replaceObjectAtIndex:[major intValue] withObject:@NO];
            }
            if (DEBUG_BEACON){
                NSLog(@"--- Exited region: %@", region);
//                UILocalNotification *notice = [[UILocalNotification alloc] init];
//                notice.alertBody = [NSString stringWithFormat:@"Exited region %@",major];
//                notice.alertAction = @"Open";
//                [[UIApplication sharedApplication] scheduleLocalNotification:notice];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateUnknown:
            if (DEBUG_BEACON) NSLog(@"Region %@ in unknown state - doing nothing...",major);
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
    NSLog(@"Ranged beacons from region 19!");
    NSLog(@"%@",beacons);
    for (CLBeacon *beacon in beacons) {
        NSString *userID = [NSString stringWithFormat:@"%@",beacon.minor];
        [self addUser:userID];
    }
}


# pragma mark - auth and status
-(void)blueToothStackIsActive
{
    self.peripheralManagerIsRunning = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Bluetooth Enabled" object:nil];
}
-(void)blueToothStackNeedsUserToActivateMessage
{
    if (IS_RUNNING_ON_SIMULATOR)
    {
        [self blueToothStackIsActive];
    } else
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"Bluetooth Disabled" object:nil];
    }
}

-(BOOL)peripheralManagerIsRunning
{
    BOOL isOK = NO;
    switch ([ CLLocationManager authorizationStatus] ) {
        case kCLAuthorizationStatusAuthorized:
            isOK = YES;
            break;
        case kCLAuthorizationStatusDenied:
            isOK = NO;
            break;
        case kCLAuthorizationStatusNotDetermined:
            isOK = NO;
            break;
        case kCLAuthorizationStatusRestricted:
            isOK = NO;
            break;
            
    }
    
    BOOL val = peripheralManagerIsRunning && isOK;
    return val;
}

-(CLLocation*)getLocation
{
    return self.locationManager.location;
}

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    // Check for supported devices
    switch ([CLLocationManager authorizationStatus])
    {
        case kCLAuthorizationStatusRestricted:
        {
            NSLog(@"kCLAuthorizationStatusRestricted");
            [self blueToothStackNeedsUserToActivateMessage];
        }
            break;
            
        case kCLAuthorizationStatusDenied:
        {
            NSLog(@"kCLAuthorizationStatusDenied");
            [self blueToothStackNeedsUserToActivateMessage];
        }
            break;
            
        case kCLAuthorizationStatusAuthorized:
        {
            NSLog(@"kCLAuthorizationStatusAuthorized");
            [self blueToothStackIsActive];
        }
            break;
            
        case kCLAuthorizationStatusNotDetermined:
        {
            NSLog(@"kCLAuthorizationStatusNotDetermined");//user has not yet said yes or no
        }
            break;
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error
{
    NSLog(@"Region monitoring failed with error: %@", [error localizedDescription]);
    
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"ERROR - %@",error);
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region
{
    NSLog(@"Started monitoring for regino: %@",region);
}

@end
