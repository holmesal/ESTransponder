//
//  ESTransponder.h
//  Earshot
//
//  Created by Alonso Holmes on 4/1/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

@interface ESTransponder : NSObject

// TODO - make this a singleton
//#define SINGLETON_IDENTIFIER @"CB284D88-5317-4FB4-9621-C5A3A49E6155"
#define IDENTIFIER_STRING @"CB284D88-5317-4FB4-9621-C5A3A49E6155"
#define IBEACON_UUID @"BC43DDCC-AF0C-4A69-9E75-4CDFF8FD5F63"
//#define IBEACON_UUID @"B9407F30-F5F8-466E-AFF9-25556B57FE6D"

@property (strong, nonatomic) NSString *earshotID;
@property (strong, nonatomic) NSMutableDictionary *earshotUsers;
@property (nonatomic, readonly) BOOL isDetecting;
@property (nonatomic, readonly) BOOL isBroadcasting;
@property (nonatomic) BOOL peripheralManagerIsRunning;

// Init with an earshotID and a firebase URL
- (id)initWithEarshotID:(NSString *)userID andFirebaseRootURL:(NSString *)firebaseURL;

// Init the firebase with a base URL
- (void)initFirebase:(NSString *)baseURL;

// Sets the earshot id, and starts advertising it.
- (void)setEarshotID:(NSString *)earshotID;

// Starts detecting core bluetooth peripherals (service method)
- (void)startDetecting;

// Starts broadcasting as a core bluetooth peripheral.
// Make sure to set earshotID first.
- (void)startBroadcasting;

// Chirp the iBeacon for a few seconds to wake up others
- (void)chirpBeacon;

// If you're doing bluetooth stuff, stop it. Just stop.
- (void)resetBluetooth;

// Gets an array of earshot ids, one for each user currently in-range
//- (NSArray *)getUsersInRange;

// Gets the current location
- (CLLocation *)getLocation;

// Events API
/*
 earshotDiscover - fired when a CoreBluetooth user is discovered. The user may or may not have a earshotID yet. Data contains the user that was just discovered, as well as a list of all the users that have been discovered so far
 
 */

@end
