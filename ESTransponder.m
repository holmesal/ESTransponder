//
//  ESTransponder.m
//  Earshot
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import "ESTransponder.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "ESBeacon.h"

// Extensions
#import "CBCentralManager+Ext.h"
#import "CBPeripheralManager+Ext.h"
#import "CBUUID+Ext.h"

#define DEBUG_CENTRAL NO
#define DEBUG_PERIPHERAL YES
#define DEBUG_BEACON YES

@interface ESTransponder() <CBPeripheralManagerDelegate, CBCentralManagerDelegate>
@property (strong, nonatomic) CBUUID *identifier;
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) NSMutableDictionary *earshotUsers;
@property (strong, nonatomic) NSNotificationCenter *note;

//@property (strong, nonatomic)

@end

@implementation ESTransponder
@synthesize earshotID;

- (id)init
{
    if ((self = [super init])) {
        self.identifier = [CBUUID UUIDWithString:IDENTIFIER_STRING];
        self.earshotUsers = [[NSMutableDictionary alloc] init];
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
    
    NSDictionary *advertisingData = @{CBAdvertisementDataServiceUUIDsKey:@[self.identifier], CBAdvertisementDataLocalNameKey:self.earshotID};
    
    // Start advertising over BLE
    [self.peripheralManager startAdvertising:advertisingData];
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




#pragma mark - iBeacon
// Below lie the functions for interacting with iBeacon
- (void)chirpBeacon
{
    if (DEBUG_BEACON) {
        NSLog(@"Chirping beacon!");
    }
    
    // Find the first available region - hardcode for now
    self.beaconUUID = [[NSUUID alloc] initWithUUIDString: @"BC43DDCC-AF0C-4A69-9E75-4CDFF8FD5F63"];
    self.beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:self.beaconUUID major:1 minor:1 identifier:@"Region 1"];
    
    // Broadcast for like 3 seconds
    NSDictionary *beaconData = [self.beaconRegion peripheralDataWithMeasuredPower:nil];
    [self.beaconManager startAdvertising:beaconData];
    
    // Do we have to turn on here first?
    
}




@end
