//
//  ESTransponder.h
//  Transponder
//
//  Created by Alonso Holmes @ MTNLAB on 4/1/14.
//  Copyright (c) 2014 MTNLAB. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

@interface ESTransponder : NSObject


// Old shortwave identifiers
//#define IDENTIFIER_STRING @"CB284D88-5317-4FB4-9621-C5A3A49E6155"
//#define IDENTITY_BEACON_UUID @"A48639FC-CC79-4A8E-8E35-DF080B9C72E3"

// New transponder identifiers
#define IDENTIFIER_STRING @"5B464730-0826-47AF-BD7C-FFD3F3AD3A82"
#define IDENTITY_BEACON_UUID @"B556F8D0-34DF-4CA6-9193-CC79FACFAE1E"

// Debugging behavior after a reboot is no fun. Turn this on to get local notifications when the bluetooth stack state changes.
#define SHOW_DEBUG_NOTIFICATIONS YES

typedef enum
{
    ESTransponderStackStateUnknown = 0,
    ESTransponderStackStateActive,
    ESTransponderStackStateDisabled
} ESTransponderStackState;

@property (assign, readonly) ESTransponderStackState isRunning;
@property (assign, nonatomic) BOOL showDebugNotifications;


@property (strong, nonatomic) NSString *transponderID;
@property (strong, nonatomic) NSArray *transponderUsers;


// Methods API

// Returns the shared ESTransponder instance
+ (ESTransponder *)sharedInstance;

// Starts broadcasting and detecting, will ask for Bluetooth and Location permissions
- (void)startTransponder;



// Events API

// Emitted when the array of users in range is updated. This is the main event that you should listen to.
// userInfo.transponderUsers is an array of dictionaries, each containing transponder uuid and last seen timestamp (unix)
#define TransponderDidUpdateUsersInRange @"TransponderDidUpdateUsersInRange"

// Emitted when a new user is discovered, but we're not sure who it is yet
// This is useful for sending "User Nearby" notifications, if you're throttling them yourself
#define TransponderAnonymousUserDiscovered @"TransponderAnonymousUserDiscovered"

// Emitted when a new user is discovered, and that user has an ID
// userInfo.uuid is the transponder uuid of the discovered user
#define TransponderUserDiscovered @"TransponderUserDiscovered"

// Emitted when Transponder thinks you should send a "YOUR-APP user nearby!" local notification
// Based on a combination of (coarse, cell-based, low-power) geolocation and a 20 minute timeout.
#define TransponderSuggestsDiscoveryNotification @"TransponderSuggestsDiscoveryNotification"

// Emitted when Transponder is successfully initialized and running
#define TransponderEnabled @"TransponderEnabled"

// Emitted if Transponder fails to start, for example, because a user denies permissions
#define TransponderDisabled @"TransponderDisabled"


@end
