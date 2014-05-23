//
//  TransponderViewController.m
//  
//
//  Created by Ethan Sherr on 5/22/14.
//
//

#import "TransponderViewController.h"
#import <Accounts/Accounts.h>
#import "TwitterCell.h"
#import "ESTransponder.h"
@interface TransponderViewController () <UITableViewDataSource, UITableViewDelegate>

#define Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore @"Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore"

//logics
typedef NS_ENUM(NSUInteger, TransponderView)
{
    
    /*! Flush automatically: periodically (once a minute or every 100 logged events) and always at app reactivation. */
    TransponderViewShowInfo = 5,
    TransponderViewTwitterView,
    TransponderViewPermissionsView
    
};
@property (strong, nonatomic) NSArray *twitterAccounts;
//ui
@property (strong, nonatomic) IBOutlet UIView *view;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;

@property (weak, nonatomic) IBOutlet UIView *showInfo;
@property (weak, nonatomic) IBOutlet UIView *twitterView;
@property (weak, nonatomic) IBOutlet UIView *permissionsView;


//show info variables
@property (weak, nonatomic) IBOutlet UIButton *twitterButton;
@property (strong, nonatomic) void (^completion)(NSError *error);

//twitter users table view
@property (weak, nonatomic) IBOutlet UITableView *twitterTableView;
@property (strong, nonatomic) NSCache *cache; //image cache for profile pics



@end

@implementation TransponderViewController;

@synthesize completion;

@synthesize cancelButton;

//showInfo variables
@synthesize showInfo;
@synthesize twitterButton;


//twitter list variables
@synthesize twitterView;
@synthesize twitterTableView;
@synthesize cache;

//permissionsView stuff
@synthesize permissionsView;

-(id)initWithCompletionBlock:(void(^)(NSError *error))comp
{
    if (self = [super init])
    {
        completion = comp;
    }
    return self;
}

//- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
//{
//    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
//    if (self)
//    {
//        // Custom initialization
//        
//    }
//    return self;
//}


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [twitterButton addTarget:self action:@selector(twitterButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    self.showInfo.tag = TransponderViewShowInfo;
    self.twitterView.tag = TransponderViewTwitterView;
    self.permissionsView.tag = TransponderViewPermissionsView;
    
    [self.twitterView setHidden:YES];
    [self.twitterView setUserInteractionEnabled:NO];
    [self.permissionsView setHidden:YES];
    [self.permissionsView setUserInteractionEnabled:NO];
    
    twitterTableView.delegate = self;
    twitterTableView.dataSource = self;
    twitterTableView.contentInset = UIEdgeInsetsMake(cancelButton.frame.origin.x+cancelButton.frame.size.height+8, 0, 8, 0);
//    [twitterTableView registerClass:[TwitterCell class] forCellReuseIdentifier:@"TwitterCell"];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


//callbacks for showInfo view
-(void)twitterButtonAction:(id)sender
{
    [twitterButton setUserInteractionEnabled:NO];
   
    ACAccountStore *account = [[ACAccountStore alloc] init];
    ACAccountType *accountType = [account accountTypeWithAccountTypeIdentifier:
                                  ACAccountTypeIdentifierTwitter];
    
    //show loading spinner?
    [account requestAccessToAccountsWithType:accountType options:nil
                                  completion:^(BOOL granted, NSError *error)
    {
        NSLog(@"error = %@", error.localizedDescription);
        
        self.twitterAccounts = [account
                                accountsWithAccountType:accountType];
        
        if (granted && self.twitterAccounts.count)
        {
            [self performSelectorOnMainThread:@selector(animateToShowTwitterList) withObject:nil waitUntilDone:NO];
        } else
        {
//            if (![[NSUserDefaults standardUserDefaults] boolForKey:Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore])
//            {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore];
                [self performSelectorOnMainThread:@selector(cancel:) withObject:[TransponderViewController generateError:TransponderErrorCodeAuthorizationDenied] waitUntilDone:NO];
                NSLog(@"not granted my twitter type thingy!");
            
//            }
        }
    }];
}

-(void)twitterRejectButtonAction:(id)sender
{
    NSLog(@"twitterRejectButtonAction");
}

-(void)animateToShowTwitterList
{
    [twitterTableView reloadData];
    [self animateFromView:showInfo toView:twitterView];
}

-(void)animateFromView:(UIView*)fromView toView:(UIView*)toView
{
    [fromView setHidden:NO];
    [fromView setUserInteractionEnabled:NO];
    [toView setHidden:NO];
    [toView setUserInteractionEnabled:YES];
    
    [toView setAlpha:0.0f];
    [toView setTransform:CGAffineTransformMakeTranslation(320, 0)];
    [fromView setTransform:CGAffineTransformIdentity];
    
    [UIView animateWithDuration:1.0 delay:0.0f usingSpringWithDamping:1.2f initialSpringVelocity:0.0f options:UIViewAnimationOptionCurveLinear animations:^
    {
//        fromView.transform = CGAffineTransformMakeTranslation(-320*2, 0);
        toView.transform = CGAffineTransformIdentity;
        fromView.alpha = 0.0f;
        toView.alpha = 1.0f;
    } completion:^(BOOL finished)
    {
//        fromView.alpha = 1.0f;
//        fromView.hidden = YES;
//        fromView.transform = CGAffineTransformIdentity;
    }];
    
}

-(void)cancel:(NSError*)error
{
    completion(error);
    [self dismissViewControllerAnimated:YES completion:^
    {}];
}

- (IBAction)cancelButtonAction:(id)sender
{
    [self cancel:[TransponderViewController generateError:TransponderErrorCodeCancel]];
}


#pragma mark UITableViewDelegate & UITableViewDataSource methods
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == twitterTableView)
    {
        return 1;
    }
    return 99999;
}
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == twitterTableView)
    {
        return 5 + self.twitterAccounts.count;
    }
    return 99999;
}
-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == twitterTableView)
    {
        TwitterCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TwitterCell"];
        if (!cell)
        {
            NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"TwitterCell" owner:self options:nil];
            // Grab a pointer to the first object (presumably the custom cell, as that's all the XIB should contain).
            cell = [topLevelObjects objectAtIndex:0];
            //asynchronous image loading into the appropriate cell!
            
        }
        
        return cell;
    }
    return nil;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == twitterTableView)
    {
        NSLog(@"selected profile %d", indexPath.row);
        
        [self animateFromView:twitterView toView:permissionsView];
        
        [self performSelector:@selector(activateBluetoothStack) withObject:nil afterDelay:1];
        
        [tableView setUserInteractionEnabled:NO];
    }
}

-(void)activateBluetoothStack
{
    [[ESTransponder sharedInstance] startTransponder];
}


//async image load helper

- (void)processImageDataWithURLString:(NSString *)urlString andBlock:(void (^)(UIImage *imageData, BOOL synchronous))processImage
{
    
    NSURL *url = [NSURL URLWithString:urlString];
    UIImage *retrievedImage = [self.cache objectForKey:url];
    if (retrievedImage)
    {
        processImage(retrievedImage, YES);
    }
    
    dispatch_queue_t callerQueue = dispatch_get_current_queue();
    dispatch_queue_t downloadQueue = dispatch_queue_create("TransponderViewControllerTwitterImage", NULL);
    dispatch_async(downloadQueue, ^
    {
        NSData * imageData = [NSData dataWithContentsOfURL:url];
        
        dispatch_async(callerQueue, ^
        {
            UIImage *img = [UIImage imageWithData:imageData];
            [cache setObject:imageData forKey:url];
            processImage(img, NO);
        });
    });
//    dispatch_release(downloadQueue);
}

-(NSCache*)cache
{
    if (!cache)
    {
        cache = [[NSCache alloc] init];
    }
    return cache;
}

/* NSError
 * helper method for returning error and error descriptions
 */
+(NSError*)generateError:(TransponderErrorCode)errorCode
{
#warning "TODO: fill out localizedDescriptionKey, localizedRecoverySuggestionErrorKey,  localizedFailureReasonErrorKey"
    /*
     * (NSLocalizedDescriptionKey)              : A localized description of the error.
     * (NSLocalizedRecoverySuggestionErrorKey)  : A localized recovery suggestion for the error.
     * (NSLocalizedFailureReasonErrorKey)       : A localized explanation of the reason for the error.
     */
    
    NSDictionary *userInfo;
    switch (errorCode) {
        case TransponderErrorCodeAuthorizationDenied:
        {
            userInfo = @{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""};
        }
        break;
        case TransponderErrorCodeLocationDenied:
        {
            userInfo = @{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""};
        }
        break;
        case TransponderErrorCodeBluetoothDenied:
        {
            userInfo = @{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""};
        }
        break;
        case TransponderErrorCodeCancel:
        {
            userInfo = @{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""};
        }
        break;
    }
    
    if (!userInfo)
    {
        return nil;
    }
    
    return [NSError errorWithDomain:TransponderDomain code:errorCode userInfo:userInfo];
}


@end
