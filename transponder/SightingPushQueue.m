//
//  SightingPushQueue.m
//  trans
//
//  Created by Ethan Sherr on 5/22/14.
//  Copyright (c) 2014 mtnlab. All rights reserved.
//

#import "SightingPushQueue.h"
#import <CoreData/CoreData.h>
#import "Sighting.h"
#import "NSObject+SBJson.h"

//#define MTNLAB_POST_URL @"http://192.168.1.90:8080/sighting" //@"http://transponder.mtnlab.io/sighting"
#define MTNLAB_POST_URL @"http://transponder.mtnlab.io/sighting"
#define MAXIMUM_POST_CAPACITY 25
#define MINIMUM_POST_INTERVAL 30.0f
#define TRANSPONDER_NSUSERDEFAULTS_LAST_POST_TIME @"TRANSPONDER_NSUSERDEFAULTS_LAST_POST_TIME"

                //updates must be 32 seconds appart OR RSSI change
#define kSAVEFILTER 32

@interface SightingPushQueue ()

@property (strong, nonatomic) NSManagedObjectContext *bgMOC;
@property (strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (strong, nonatomic) NSManagedObjectModel *managedObjectModel;
//@property (strong, nonatomic) NSNumber *lastNonZeroRssi;


@property (strong, nonatomic) NSMutableDictionary *lastReadingsDictionary;


@property (strong, nonatomic) NSTimer *postTimer;
//DOCU
/*
 * When your app is moved back to the active state, its applicationDidBecomeActive: method should reverse
 * any of the steps taken in the applicationWillResignActive: method. Thus, upon reactivation, your app
 * should restart timers, resume dispatch queues, and throttle up OpenGL ES frame rates again. However, 
 * games should not resume automatically; they should remain paused until the user chooses to resume them.
 */
 

@end

@implementation SightingPushQueue
@synthesize postTimer;
@synthesize bgMOC;

@synthesize lastReadingsDictionary;
//@synthesize lastNonZeroRssi;
-(id)init
{
    if (self = [super init])
    {
        lastReadingsDictionary = [[NSMutableDictionary alloc] init];
//        lastNonZeroRssi = @0;
    }
    return self;
}

//returns yes if we try to post
-(BOOL)throttledPost
{
    NSDate *lastPostDate = [[NSUserDefaults standardUserDefaults] objectForKey:TRANSPONDER_NSUSERDEFAULTS_LAST_POST_TIME];
    if (YES || //currently it is not throttled
        !lastPostDate ||
        fabsf([lastPostDate timeIntervalSinceNow]) >= MINIMUM_POST_INTERVAL )
    {
        [self post];
        
        return YES;
    }
    return NO;
}

-(void)post
{
    [self.bgMOC performBlock:^
    {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Sighting"];
        [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]]];
        [fetchRequest setFetchLimit:MAXIMUM_POST_CAPACITY];
        
        NSError *fetchError = nil;
        NSArray *sightings = [self.bgMOC executeFetchRequest:fetchRequest error:&fetchError];

        if (sightings &&
            sightings.count)
        {
//            BOOL isMainThread = [NSThread isMainThread];
            

            
            if (fetchError)
            {
                NSLog(@"error in fetching sightings = %@", fetchError);
            } else
            {
                NSURLRequest *postRequest = [self postRequestForSightings:sightings];
                
                NSError *requestError = nil;
                NSURLResponse *requestResponse = nil;
                NSLog(@"making a request %@", postRequest);
                NSData *responseData = [NSURLConnection sendSynchronousRequest:postRequest returningResponse:&requestResponse error:&requestError];
                NSLog(@"finished with request, resopnseData = %@", [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]);
                if (requestResponse)
                {
                    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)requestResponse;
                    int status = httpResponse.statusCode;
                    NSLog(@"status = %d", status);
                    if (status == 200)
                    {
                        //delete all these sightings!
                        for (Sighting *sighting in sightings)
                        {
                            [self.bgMOC deleteObject:sighting];
                        }
                    }

                    NSError *saveError = nil;
                    [self.bgMOC save:&saveError];
                    
                    if (saveError)
                    {
                        NSLog(@"error saving after deleting a bunch of objects for some reason.  %@", saveError);
                    }
                    
                    [self debugPrintAllSightings];
                    
                }
                
            }//end of no fetchError
        }//end of if sightings.count
        
    }];
}


-(NSURLRequest*)postRequestForSightings:(NSArray*)sightings
{
    
    NSString *jsonString = @"[";
        for (int i = 0; i < sightings.count; i++)
        {
            
            jsonString = [jsonString stringByAppendingString:[[sightings objectAtIndex:i] JSONRepresentation]];
            
            if (i < sightings.count - 1)
            {
                jsonString = [jsonString stringByAppendingString:@","];
            }
        }
    jsonString = [jsonString stringByAppendingString:@"]"];
    
//    NSDictionary *jsonDict = [jsonString JSONValue];
    
    NSURL *Url = [NSURL URLWithString:MTNLAB_POST_URL];
    
    NSData *PostData = [jsonString dataUsingEncoding:NSASCIIStringEncoding];
    NSString *postLength = [NSString stringWithFormat:@"%d", [PostData length]];
    
    NSMutableURLRequest *Request = [[NSMutableURLRequest alloc] init];
    [Request setURL:Url];
    [Request setHTTPMethod:@"POST"];
    [Request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [Request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [Request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [Request setHTTPBody:PostData];
    
    return Request;
}


- (void)addSightingWithID:(NSString *)sighted withRSSI:(NSNumber *)rssi andTimestamp:(NSNumber *)timestamp
{
    
    
    [self.bgMOC performBlock:^{
        
    //    @{
    //      @"broadcaster": broadcasterID,
    //      @"sighter": self.transponderID,
    //      @"rssi": rssi,
    //      @"timestamp": [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]
    //      };

        // Grab the uuid from userPrefs
        //get uuid
        NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"transponder-uuid"];
        
        NSDictionary *last = [lastReadingsDictionary objectForKey:sighted];
        if (last)
        {//filter how frequently i save a value to be posted
            NSNumber *timeStampLast = [last objectForKey:@"timestamp"];
            NSNumber *rssiLast = [last objectForKey:@"rssi"];
            if ([rssiLast integerValue] == [rssi integerValue])
            {
                double dt = [timestamp doubleValue] - [timeStampLast doubleValue];
//                NSLog(@"*****dt = %f",dt);
                if (dt < kSAVEFILTER)
                {
//                    NSLog(@"dt = %ld : RETURN", dt);
                    return;
                } else
                {
//                    NSLog(@"!!!all good!");
                }
                return;
            }

            
            
        }
        
        Sighting *sighting = [NSEntityDescription insertNewObjectForEntityForName:@"Sighting" inManagedObjectContext:self.bgMOC];
        sighting.sighted = sighted;
        sighting.uuid = uuid;
        sighting.rssi = rssi;//([rssi integerValue] ? rssi : lastNonZeroRssi);
        sighting.timestamp = timestamp;
        
        [lastReadingsDictionary removeObjectForKey:sighted];
        [lastReadingsDictionary setObject:[sighting dictValue] forKey:sighted];
//        lastNonZeroRssi = sighting.rssi;
        
        NSError *error = nil;
        [self.bgMOC save:&error];
        
        if (error)
        {
            NSLog(@"was unable to save dafuk, %@", error);
        }
        
        [self debugPrintAllSightings];
        
        [self post];
        
    }];
}


-(void)debugPrintAllSightings
{
//    [self.bgMOC performBlock:^
//    {
        
        NSFetchRequest *fetchAllRequest = [[NSFetchRequest alloc] initWithEntityName:@"Sighting"];
        //set predicate?
        [fetchAllRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES] ] ];
        
        
        NSError *error = nil;
        NSArray *array = [bgMOC executeFetchRequest:fetchAllRequest error:&error];
        if (error)
        {
            NSLog(@"fetch error %@", error);
        }
        
        NSLog(@"fetched %d", array.count);
//    }];

}

#pragma mark start NSManagedObjectContext setup methods
- (NSManagedObjectContext *)bgMOC
{
    if (!bgMOC)
    {
        NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
        if (coordinator != nil)
        {
            bgMOC = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            [bgMOC setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
            //NSMainQueueConcurrencyType];
            //NSMainQueueConcurrencyType];//NSPrivateQueueConcurrencyType];
            [bgMOC performBlockAndWait:^
             {
                 [bgMOC setPersistentStoreCoordinator:coordinator];
             }];
            
        }
    }
    return bgMOC;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (!_persistentStoreCoordinator)
    {
        
        NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"SightingModel.sqlite"];
        
        NSError *error = nil;
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
        {
            /*
             Replace this implementation with code to handle the error appropriately.
             
             abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
             
             Typical reasons for an error here include:
             * The persistent store is not accessible;
             * The schema for the persistent store is incompatible with current managed object model.
             Check the error message to determine what the actual problem was.
             
             
             If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
             
             If you encounter schema incompatibility errors during development, you can reduce their frequency by:
             * Simply deleting the existing store:
             [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
             
             * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
             [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
             
             Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
             
             */
            //        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            //        abort();
           
        }
    }
    
    return _persistentStoreCoordinator;
}

-(NSManagedObjectModel*)managedObjectModel
{
    if (!_managedObjectModel)
    {
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"SightingModel" withExtension:@"momd"];
        _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return _managedObjectModel;
}


// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}
#pragma mark end NSManagedObjectContext setup methods
@end
