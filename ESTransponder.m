//
//  ESTransponder.m
//  Earshot
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import "ESTransponder.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

// Extensions
#import "CBCentralManager+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBUUID+Ext.h"

#define DEBUG_CENTRAL NO
#define DEBUG_PERIPHERAL NO
#define DEBUG_BEACON YES
#define DEBUG_USERS NO

#define NUM_BEACONS 20

@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate>
// Bluetooth / main class stuff
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSNotificationCenter *note;
@property (strong, nonatomic) NSDictionary *bluetoothAdvertisingData;

// Beacon broadcasting
@property NSInteger flipCount;
@property BOOL isAdvertisingAsBeacon;
@property (strong, nonatomic) CLBeaconRegion *beaconBroadcastRegion;

// Beacon monitoring
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) NSMutableArray *regions;

@end

@implementation ESTransponder
@synthesize earshotID;

- (id)init
{
    if ((self = [super init])) {
        self.identifier = [CBUUID UUIDWithString:IDENTIFIER_STRING];
        self.earshotUsers = [[NSMutableDictionary alloc] init];
        // Start off NOT flipping between beacons/bluetooth
        self.isAdvertisingAsBeacon = NO;
        // Setup beacon monitoring for regions
        
        
        
//        [self performSelector:@selector(setupBeaconRegions) withObject:nil afterDelay:5];
        [self setupBeaconRegions];
    }
    return self;
}

- (void)setEarshotID:(NSString *)earshitId
{
    earshotID = earshitId;
}

- (NSArray *)getUsersInRange
{
    NSMutableArray *usersInRange = [[NSMutableArray alloc] init];
    // Loop through the current users and add any in-range users, killing dupes
    for(NSMutableDictionary *userBeaconKey in self.earshotUsers)
    {
        NSMutableDictionary *userBeacon = [self.earshotUsers objectForKey:userBeaconKey];
        if ([userBeacon valueForKey:@"earshotID"] != [NSNull null])
        {
            if (![usersInRange containsObject:[userBeacon valueForKey:@"earshotID"]])
            {
                [usersInRange addObject:[userBeacon valueForKey:@"earshotID"]];
            } else{
                if (DEBUG_USERS) {NSLog(@"NOT ADDING - DUPE");}
            }
        } else{
            if (DEBUG_USERS){NSLog(@"NOT ADDING - EMPTY");}
        }
    }
    if (DEBUG_USERS){NSLog(@"user array - %@",usersInRange);}
    return [[NSArray alloc] initWithArray:usersInRange];
}

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
    NSLog(@"Scanning!");
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
    NSMutableDictionary *existingUser = [self.earshotUsers objectForKey:[peripheral.identifier UUIDString]];
    if ([existingUser count] == 0) {
        // No user yet, make one
        NSMutableDictionary *newUser = [[NSMutableDictionary alloc] initWithDictionary:@{@"lastSeen": [[NSDate alloc] init],
                                                                                         @"earshotID": [NSNull null]}];
        // Insert
        [self.earshotUsers setObject:newUser forKey:[peripheral.identifier UUIDString]];
        
        // Alias
        existingUser = newUser;
        
        // Send the new (anonymous) user notification
        [self.note postNotificationName:@"newUserDiscovered" object:@{@"user":existingUser}];
    } else{
        // Update the time last seen
        [existingUser setObject:[[NSDate alloc] init] forKey:@"lastSeen"];
    }
    
    // Update local name if included in advertisement
    NSString *localName = [advertisementData valueForKey:@"kCBAdvDataLocalName"];
    if (localName){
        [existingUser setValue:localName forKey:@"earshotID"];
    }
    
    if (DEBUG_CENTRAL) {
        NSLog(@"%@",self.earshotUsers);
    }
    
    // Notify peeps that an earshot user was discovered
    [self.note postNotificationName:@"earshotDiscover" object:@{@"user":existingUser,
                                                                @"earshotUsers":[self getUsersInRange]}];
    
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (DEBUG_CENTRAL)
        NSLog(@"-- central state changed: %@", self.centralManager.stateString);
    
    if (central.state == CBCentralManagerStatePoweredOn) {
        [self startScanning];
    }
}

#pragma mark - CBPeripheralManagerDelegate
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    if (DEBUG_PERIPHERAL)
        NSLog(@"-- peripheral state changed: %@", peripheral.stateString);
    
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
    
    NSLog(@"Attempting to create new beacon!");
    
    // Find an available uuid
    bool found = NO;
    NSNumber *availableRegion = 0;
    for (int minor=0; minor<NUM_BEACONS; minor++) {
        if (![[self.regions objectAtIndex:minor] boolValue]) {
            NSLog(@"Region %i will have to do.",minor);
            availableRegion = [NSNumber numberWithInt:minor];
            found = YES;
            break;
        } else {
            NSLog(@"Region %i is in use.",minor);
        }
    }
    
    // Was anything found?
    if (found) {
        NSLog(@"Creating a new beacon broadcast region in slot number %@",availableRegion);
        self.beaconBroadcastRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                             major:0
                                                                             minor:16
                                                                        identifier:@"Earshot Region"];
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
    NSLog(@"Advertising as beacon? %@",self.isAdvertisingAsBeacon ? @"true" : @"false");
    // Do whatever that is
    if (self.isAdvertisingAsBeacon){
        [self startBeacon];
    } else{
        [self resetBluetooth];
    }
    NSLog(@"Flipping!");
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
        NSLog(@"Starting to monitor for region %i",minor);
        // Start outside the region
        [self.regions addObject:@NO];
        // Create a region with this minor
        CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                         major:0
                                                                         minor:minor
                                                                    identifier:@"Earshot Region"];
        // Wake up the app when you enter this region
        region.notifyEntryStateOnDisplay = YES;
        region.notifyOnEntry = YES;
        region.notifyOnExit = YES;
        // Start monitoring via location manager
        [self.locationManager startMonitoringForRegion:region];
        // OPTIONAL - if we need to initialize this region with an inside/outside state, do it here
//        [self.locationManager performSelector:@selector(requestStateForRegion:) withObject:region afterDelay:5];
        [self.locationManager requestStateForRegion:region];
    }
    
    
}

#pragma mark - CLLocationManagerDelegate

- (void) locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    NSLog(@"Did enter region! %@",region);
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    // What region?
    NSNumber *minor = [region valueForKey:@"minor"];
//    NSLog(@"Got state %@ for region %@ : %@",state,minor,region);
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
            if (DEBUG_BEACON){
                NSLog(@"--- Exited region: %@", region);
                UILocalNotification *notice = [[UILocalNotification alloc] init];
                notice.alertBody = [NSString stringWithFormat:@"Exited region %@",minor];
                notice.alertAction = @"Open";
                [[UIApplication sharedApplication] scheduleLocalNotification:notice];
                NSLog(@"%@",self.regions);
            }
            [self.regions replaceObjectAtIndex:[minor intValue] withObject:@NO];
            break;
        case CLRegionStateUnknown:
            NSLog(@"Region %@ in unknown state - doing nothing...",minor);
            break;
        default:
            NSLog(@"This is never supposed to happen.");
            break;
    }
}




@end
