//
//  Sighting.h
//  trans
//
//  Created by Ethan Sherr on 5/22/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Sighting : NSManagedObject

@property (nonatomic, retain) NSString * broadcaster;
@property (nonatomic, retain) NSString * sighter;
@property (nonatomic, retain) NSNumber * rssi;
@property (nonatomic, retain) NSNumber * timestamp;

-(NSString*)JSONRepresentation;

@end
