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

#define DEBUG_CENTRAL YES
#define DEBUG_PERIPHERAL YES
#define DEBUG_BEACON NO
#define DEBUG_USERS YES

#define IS_RUNNING_ON_SIMULATOR NO

#define NUM_BEACONS 20

@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate>
// Bluetooth / main class stuff
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSDictionary *bluetoothAdvertisingData;
@property (strong, nonatomic) NSMutableDictionary *bluetoothUsers;

// Beacon broadcasting
@property NSInteger flipCount;
@property BOOL isAdvertisingAsBeacon;
@property (strong, nonatomic) CLBeaconRegion *beaconBroadcastRegion;

// Beacon monitoring
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) NSMutableArray *regions;

// Firebase-synced users array
@property (strong, nonatomic) Firebase *rootRef;
@property (strong, nonatomic) Firebase *earshotUsersRef;
//@property (strong, nonatomic) NSMutableDictionary *earshotUsers;

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
        // Start off NOT flipping between beacons/bluetooth
        self.isAdvertisingAsBeacon = NO;
        // Setup beacon monitoring for regions
        [self setupBeaconRegions];
        // Start a repeating timer to prune the in-range users, every 10 seconds
        [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(pruneUsers) userInfo:nil repeats:YES];
    }
    return self;
}
//
//- (void)setEarshotID:(NSString *)earshitId
//{
//    earshotID = earshitId;
//    // Set up firebase
//    //    [self initFirebase];
//}

//# pragma mark - user management
//- (NSArray *)getUsersInRange
//{
//    NSMutableArray *usersInRange = [[NSMutableArray alloc] init];
//    // Loop through the current users and add any in-range users, killing dupes
//    for(NSMutableDictionary *userBeaconKey in self.bluetoothUsers)
//    {
//        NSMutableDictionary *userBeacon = [self.bluetoothUsers objectForKey:userBeaconKey];
//        if ([userBeacon valueForKey:@"earshotID"] != [NSNull null])
//        {
//            if (![usersInRange containsObject:[userBeacon valueForKey:@"earshotID"]])
//            {
//                [usersInRange addObject:[userBeacon valueForKey:@"earshotID"]];
//            } else{
//                if (DEBUG_USERS) {NSLog(@"NOT ADDING - DUPE");}
//            }
//        } else{
//            if (DEBUG_USERS){NSLog(@"NOT ADDING - EMPTY");}
//        }
//    }
//    if (DEBUG_USERS) NSLog(@"user array - %@",usersInRange);
//    return [[NSArray alloc] initWithArray:usersInRange];
//}

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
        if (lastSeen > 20.0) {
            if (DEBUG_USERS) NSLog(@"Removing user: %@",userBeacon);
            // Remove from earshotUsers
            [self removeUser:[userBeacon objectForKey:@"earshotID"]];
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
        }
    }];
}

// Takes in a bluetooth user and adds it to earshotUsers
- (void)addUser:(NSString *)userID
{
    // Add the user for yourself
    [[self.earshotUsersRef childByAppendingPath:userID] setValue:@"true"];
    // Add yourself for the user
    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.earshotID] setValue:@"true"];
}

- (void)removeUser:(NSString *)userID
{
#warning not sure this is the right way to handle removing users...
    // Remove the user for yourself
    [[self.earshotUsersRef childByAppendingPath:userID] removeValue];
    // Remove yourself for the user
    [[[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.earshotID] removeValue];
}

//// Syncs the users currently in earshotUsers to firebase for both this user and the other users
//- (void)syncOtherUserToFirebase:(NSString *)target
//{
//    // Fake a bluetooth dictionary
//    [self.earshotUsersRef setValue:self.earshotUsers];
//}
//- (void)syncDiscoveredUserToFirebase:(NSString *)userID
//{
////    NSLog(@"Syncing user %@ to firebase", userID);
//    // Is this user already in the array?
//    NSDictionary *existingUser = [self.earshotUsers objectForKey:userID];
//    if ([existingUser count] == 0) {
//        NSLog(@"No existing user");
//        NSDictionary *trackingUser = @{@"place":@"holder"};
//        [self.earshotUsers setObject:trackingUser forKey:userID];
//        // Update!
//        [self.earshotUsersRef setValue:self.earshotUsers];
//        // Now go tell the other person
//        Firebase *otherPersonRef = [[[[self.rootRef childByAppendingPath:@"users"] childByAppendingPath:userID] childByAppendingPath:@"tracking"] childByAppendingPath:self.earshotID];
//        [otherPersonRef setValue:trackingUser];
//    } else{
//        NSLog(@"Existing user found!");
//    }
////    NSLog(@"Existing user looks like %@",userString);
//
//}
//
//- (void)removeLostUserFromFirebase:(NSString *)userID
//{
//    NSLog(@"Removing user %@ from firebase",userID);
//    [self.earshotUsers removeObjectForKey:userID];
//    // Update!
//    [self.earshotUsersRef setValue:self.earshotUsers];
//    NSLog(@"Firebase users -- %@",self.earshotUsers);
////    NSDictionary *existingUser = [self.earshotUsers objectForKey:userID];
////    if ([existingUser count] == 0) {
////        NSLog(@"Removing user %@ from firebase",userID);
////    } else{
////        NSLog(@"Removing user!");
////        [self.earshotUsers removeObjectForKey:userID];
////        // Update!
////        [self.earshotUsersRef setValue:self.earshotUsers];
////    }
//}

# pragma mark - core bluetooth

- (void)startDetecting
{
    //    if (![self canMonitorTransponders])
    //        return;
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
    } else{
        // Update the time last seen
        [existingUser setObject:[[NSDate alloc] init] forKey:@"lastSeen"];
    }
    
    // Update local name if included in advertisement
    NSString *localName = [advertisementData valueForKey:@"kCBAdvDataLocalName"];
    if (localName){
        [existingUser setValue:localName forKey:@"earshotID"];
        // Add to earshot users
        [self addUser:localName];
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
// Below lie the functions for interacting with iBeacon
- (void)chirpBeacon
{
    
    if (DEBUG_BEACON) NSLog(@"Attempting to create new beacon!");
    
    // Find an available uuid
    bool found = NO;
    NSNumber *availableRegion = 0;
    for (int minor=0; minor<NUM_BEACONS; minor++) {
        if (![[self.regions objectAtIndex:minor] boolValue]) {
            if (DEBUG_BEACON) NSLog(@"Region %i will have to do.",minor);
            availableRegion = [NSNumber numberWithInt:minor];
            found = YES;
            break;
        } else {
            if (DEBUG_BEACON) NSLog(@"Region %i is in use.",minor);
        }
    }
    
    // Was anything found?
    if (found) {
        if (DEBUG_BEACON) NSLog(@"Creating a new beacon broadcast region in slot number %@",availableRegion);
        self.beaconBroadcastRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                             major:0
                                                                             minor:[availableRegion intValue]
                                                                        identifier:[NSString stringWithFormat:@"Broadcast region %@",availableRegion]];
        // Reset the flip count
        self.flipCount = 0;
        // Flip!
        [self flipState];
    } else{
        int timeoutSeconds = 10;
        NSLog(@"Couldn't find an open region, trying again in %i seconds.",timeoutSeconds);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,  timeoutSeconds*1000* NSEC_PER_MSEC), dispatch_get_main_queue(),                ^{
            [self chirpBeacon];
        });
    }
}

- (void)flipState
{
    // Do whatever you're not doing right now
    self.isAdvertisingAsBeacon = !self.isAdvertisingAsBeacon;
    if (DEBUG_BEACON) NSLog(@"Advertising as beacon? %@",self.isAdvertisingAsBeacon ? @"true" : @"false");
    // Do whatever that is
    if (self.isAdvertisingAsBeacon){
        [self startBeacon];
    } else{
        [self resetBluetooth];
    }
    if (DEBUG_BEACON) NSLog(@"Flipping!");
    // Maximum number of flips
    NSInteger maxFlips = 10;
    // Set timeout if flip state < maxflips
    if(self.flipCount < maxFlips)
    {
        self.flipCount++;
        // Change the advertising method, so the next wakeup has it
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,  1000* NSEC_PER_MSEC), dispatch_get_main_queue(),                ^{
            [self flipState];
        });
        
    } else
    {
        [self resetBluetooth];
    }
    
}

- (void)resetBluetooth
{
    if (DEBUG_BEACON)
        NSLog(@"-- resetting to broadcast as bluetooth");
    // Stop what you're doing and advertise with bluetooth
    [self.peripheralManager stopAdvertising];
    self.isAdvertisingAsBeacon = NO;
    [self.peripheralManager startAdvertising:self.bluetoothAdvertisingData];
}

- (void)startBeacon
{
    if (DEBUG_BEACON)
        NSLog(@"-- starting to broadcast as beacon");
    // Stop what you're doing and advertise as a beacon
    [self.peripheralManager stopAdvertising];
    // Broadcast
    NSDictionary *beaconData = [self.beaconBroadcastRegion peripheralDataWithMeasuredPower:nil];
    [self.peripheralManager startAdvertising:beaconData];
}


# pragma mark - iBeacon discovery
// Starts monitoring regions for minors 0-NUM_BEACONS
- (void)setupBeaconRegions
{
    NSLog(@"Setting up beacon regions...");
    // Make the location manager
    self.locationManager = [[CLLocationManager alloc] init];
    // Set the delegate
    self.locationManager.delegate = self;
    // Init the region tracker
    self.regions = [[NSMutableArray alloc] init];
    
    // Loop through the minors 1-20, and set up a region for each one
    for (int minor=0; minor<NUM_BEACONS; minor++) {
        if (DEBUG_BEACON) NSLog(@"Starting to monitor for region %i",minor);
        // Start outside the region
        [self.regions addObject:@NO];
        // Create a region with this minor
        CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                         major:0
                                                                         minor:minor
                                                                    identifier:[NSString stringWithFormat:@"Listen region %d",minor]];
        // Wake up the app when you enter this region
        region.notifyEntryStateOnDisplay = YES;
        region.notifyOnEntry = YES;
        region.notifyOnExit = YES;
        // Start monitoring via location manager
        [self.locationManager startMonitoringForRegion:region];
        // OPTIONAL - if we need to initialize this region with an inside/outside state, do it here
        [self.locationManager requestStateForRegion:region];
    }
    
    
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    // What region?
    NSNumber *minor = [region valueForKey:@"minor"];
    //    NSLog(@"Got state %li for region %@ : %@",state,minor,region);
    switch (state) {
        case CLRegionStateInside:
            [self.regions replaceObjectAtIndex:[minor intValue] withObject:@YES];
            if (DEBUG_BEACON){
                NSLog(@"--- Entered region: %@", region);
                UILocalNotification *notice = [[UILocalNotification alloc] init];
                notice.alertBody = [NSString stringWithFormat:@"Entered region %@",minor];
                notice.alertAction = @"Open";
                [[UIApplication sharedApplication] scheduleLocalNotification:notice];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateOutside:
            [self.regions replaceObjectAtIndex:[minor intValue] withObject:@NO];
            if (DEBUG_BEACON){
                NSLog(@"--- Exited region: %@", region);
                //                UILocalNotification *notice = [[UILocalNotification alloc] init];
                //                notice.alertBody = [NSString stringWithFormat:@"Exited region %@",minor];
                //                notice.alertAction = @"Open";
                //                [[UIApplication sharedApplication] scheduleLocalNotification:notice];
                NSLog(@"%@",self.regions);
            }
            break;
        case CLRegionStateUnknown:
            if (DEBUG_BEACON) NSLog(@"Region %@ in unknown state - doing nothing...",minor);
            break;
        default:
            NSLog(@"This is never supposed to happen.");
            break;
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




@end
