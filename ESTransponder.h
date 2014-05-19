//
//  ESTransponder.h
//  transponder
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

@interface ESTransponder : NSObject

//#define SINGLETON_IDENTIFIER @"CB284D88-5317-4FB4-9621-C5A3A49E6155"
#define IDENTIFIER_STRING @"CB284D88-5317-4FB4-9621-C5A3A49E6155"
//#define IBEACON_UUID @"BC43DDCC-AF0C-4A69-9E75-4CDFF8FD5F63"
#define IDENTITY_BEACON_UUID @"A48639FC-CC79-4A8E-8E35-DF080B9C72E3"
//#define IBEACON_UUID @"B9407F30-F5F8-466E-AFF9-25556B57FE6D"
//#define kTransponderEventTransponderEnabled @"Bluetooth Enabled"
//#define kTransponderEventTransponderDisabled @"Bluetooth Disabled"
//#define kTransponderTriggerChirpBeacon @"chirpBeacon"
//#define kTransponderEventCountUpdated @"WHO DAT"

#define kTransponderEventTransponderUserDiscovered @"transponderDiscover"
//nobody listens to the bellow
//#define kTransponderEventNewUserDiscovered @"newUserDiscovered"

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


// Init with an transponderID and a firebase URL
//- (id)initWithTransponderID:(NSString *)userID andFirebaseRootURL:(NSString *)firebaseURL;

// Init the firebase with a base URL
//- (void)initFirebase:(NSString *)baseURL;

// Sets the transponder id, and starts advertising it.
//- (void)setTransponderID:(NSString *)transponderID;

// Starts detecting core bluetooth peripherals (service method)
//- (void)startDetecting;

// Starts broadcasting as a core bluetooth peripheral.
// Make sure to set transponderID first.
//- (void)startBroadcasting;

// Chirp the iBeacon for a few seconds to wake up others
//- (void)chirpBeacon;

// Shorthand for startDetecting, startBroadcasting, and chirpBeacon
//- (void)startAwesome;

// If you're doing bluetooth stuff, stop it. Just stop.
//- (void)resetBluetooth;

// Gets an array of transponder ids, one for each user currently in-range
//- (NSArray *)getUsersInRange;

// Gets the current location
//- (CLLocation *)getLocation;





// Methods API

// Returns the shared ESTransponder instance
+ (ESTransponder *)sharedInstance;

// Starts broadcasting and detecting, will ask for Bluetooth and Location permissions
- (void)startTransponder;



// Events API

// Emitted when the array of users in range is updated
#define TransponderDidUpdateUsersInRange @"TransponderDidUpdateUsersInRange"

// Emitted when a new user is discovered, but we're not sure who it is yet
// This is useful for sending "User Nearby" notifications
#define TransponderAnonymousUserDiscovered @"TransponderAnonymousUserDiscovered"

// Emitted when Transponder is successfully initialized and running
#define TransponderEnabled @"TransponderEnabled"

// Emitted if Transponder fails to start, for example, because a user denies permissions
#define TransponderDisabled @"TransponderDisabled"


@end
