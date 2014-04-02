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
//#import "ESBeacon.h"

// Extensions
#import "CBCentralManager+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBUUID+Ext.h"

#define DEBUG_CENTRAL YES
#define DEBUG_PERIPHERAL NO
#define DEBUG_BEACON YES

@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate>
// Bluetooth / main class stuff
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSMutableDictionary *earshotUsers;
@property (strong, nonatomic) NSNotificationCenter *note;
@property (strong, nonatomic) NSDictionary *bluetoothAdvertisingData;

// Beacon broadcasting
@property NSInteger flipCount;
@property BOOL isAdvertisingAsBeacon;
@property (strong, nonatomic) CLBeaconRegion *beaconBroadcastRegion;

// Beacon monitoring
@property (strong, nonatomic) CLLocationManager *locationManager;



//@property (strong, nonatomic)

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
        [self setupBeaconRegions];
    }
    return self;
}

- (void)setEarshotID:(NSString *)earshitId
{
    earshotID = earshitId;
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
                                                                @"earshotUsers":self.earshotUsers}];
    
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
    
    NSLog(@"Creating new beacon!");
    
    // Find an available uuid - hardcoded for now
    self.beaconBroadcastRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                major:0
                                                                minor:0
                                                           identifier:@"Earshot Region"];
    
    // Create a new ESBeacon and chirp that shit
//    self.beacon = [[ESBeacon alloc] init];
    
    // Reset the flip count
    self.flipCount = 0;
    // Flip!
    [self flipState];

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
// Starts monitoring regions for minors 0-19
- (void)setupBeaconRegions
{
    // Make the location manager
    self.locationManager = [[CLLocationManager alloc] init];
    // Set the delegate
    self.locationManager.delegate = self;
    
    // Create a region with this minor
    CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: IBEACON_UUID]
                                                                     major:0
                                                                     minor:0
                                                                identifier:@"Earshot Region"];
    // Wake up the app when you enter this region
    region.notifyEntryStateOnDisplay = YES;
    // Start monitoring via location manager
    [self.locationManager startMonitoringForRegion:region];
    // OPTIONAL - if we need to initialize this region with an inside/outside state, do it here
    [self.locationManager requestStateForRegion:region];
}

#pragma mark - CLLocationManagerDelegate

//- (void)locationManager:(CLLocationManager *)manager
//	  didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
//{
//    NSLog(@"State is %ld for region %@", state, region);
//    if (state == CLRegionStateInside)
//    {
//        if (DEBUG_BEACON)
//            NSLog(@"-- Entered beacon region: %@", region);
//        
//        UILocalNotification *notice = [[UILocalNotification alloc] init];
//    
//        notice.alertBody = @"Entered region!";
//        notice.alertAction = @"Open";
//    
//        [[UIApplication sharedApplication] scheduleLocalNotification:notice];
//    }
//
//}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    if (DEBUG_BEACON)
        NSLog(@"+++ Entered beacon region: %@", region);
    
    UILocalNotification *notice = [[UILocalNotification alloc] init];
    
    notice.alertBody = @"Entered region!";
    notice.alertAction = @"Open";
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notice];
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
    if (DEBUG_BEACON)
        NSLog(@"--- Exited beacon region: %@", region);
    
    UILocalNotification *notice = [[UILocalNotification alloc] init];
    
    notice.alertBody = @"Exited region!";
    notice.alertAction = @"Open";
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notice];
}




@end
