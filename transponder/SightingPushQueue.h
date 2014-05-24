//
//  SightingPushQueue.h
//  trans
//
//  Created by Ethan Sherr on 5/22/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SightingPushQueue : NSObject

-(void)addObjectToQueue:(NSDictionary*)sightingDictionary;

//returns yes if it is ~time to post, no if we still have some time to wait;
-(BOOL)throttledPost;
-(void)post;
-(void)debugPrintAllSightings;
@end
