//
//  Sighting.m
//  trans
//
//  Created by Ethan Sherr on 5/22/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import "Sighting.h"

#import "NSObject+SBJson.h"

@implementation Sighting

@dynamic sighted;
@dynamic uuid;
@dynamic rssi;
@dynamic timestamp;

-(NSDictionary*)dictValue
{
    NSLog(@"Timestamp is %@", self.timestamp);
    return @{@"sighted":self.sighted,
             @"uuid":self.uuid,
             @"rssi":self.rssi,
             @"timestamp":self.timestamp};
}

-(NSString*)JSONRepresentation
{
    return [self.dictValue JSONRepresentation];
}

@end
