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

@property (nonatomic, retain) NSString * sighted;
@property (nonatomic, retain) NSString * uuid;
@property (nonatomic, retain) NSNumber * rssi;
@property (nonatomic, retain) NSNumber * timestamp;

-(NSString*)JSONRepresentation;

@end
