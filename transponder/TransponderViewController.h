//
//  TransponderViewController.h
//  
//
//  Created by Ethan Sherr on 5/22/14.
//
//

#import <UIKit/UIKit.h>

@interface TransponderViewController : UIViewController

-(id)initWithCompletionBlock:(void(^)(NSError *error))comp;

@end
