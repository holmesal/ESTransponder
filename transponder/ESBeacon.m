//
//  ESBeacon.m
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import "ESBeacon.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

// Extensions
#import "CBPeripheralManager+Ext.h"

#define DEBUG_BEACON YES

@interface ESBeacon() <CBPeripheralManagerDelegate, CBPeripheralManagerDelegate>
@property CBPeripheralManager *peripheralManager;
@property CLBeaconRegion *beaconRegion;
@property (strong, nonatomic) NSTimer *testTimer;
@end

@implementation ESBeacon

- (id)init
{
    if ((self = [super init])) {
        self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
        
        self.testTimer = [NSTimer scheduledTimerWithTimeInterval:5.0f target:self
                                                            selector:@selector(chirpBeacon)
                                                            userInfo:nil repeats:NO];
    }
    return self;
}

- (void)chirpBeacon
{
    if (DEBUG_BEACON)
        NSLog(@"Chirping beacon!");
    
    // Find the first available region - hardcode for now
    self.beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString: EARSHOT_UUID]
                                                                major:1
                                                                minor:1
                                                           identifier:@"Region 1"];
    
    // Broadcast for like 3 seconds
    NSDictionary *beaconData = [self.beaconRegion peripheralDataWithMeasuredPower:nil];
    [self.peripheralManager startAdvertising:beaconData];
}


#pragma mark - CBPeripheralManagerDelegate
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    if (DEBUG_BEACON)
        NSLog(@"-- peripheral state changed: %@", peripheral.stateString);
    
    if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
//        [self chirpBeacon];
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (DEBUG_BEACON) {
        if (error)
            NSLog(@"error starting advertising: %@", [error localizedDescription]);
        else
            NSLog(@"did start advertising!");
    }
}



@end
