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
#import "NSObject+SBJson.h"
#import "ESTransponder.h"
@interface TransponderViewController () <UIWebViewDelegate>

//api-key is client id
#define API_KEY @"75dw0dma8ftq8g"
#define SECRET_KEY @"4qvkOmdL2HTRLty5"
#define SCOPE @"r_fullprofile%20r_emailaddress%20r_network%20rw_groups"
#define STATE @"SDLFIIHOIHENONFihsodfhi"
#define REDIRECTURI @"http://www.google.com"


#define Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore @"Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore"

//logics
typedef NS_ENUM(NSUInteger, TransponderView)
{
    
    /*! Flush automatically: periodically (once a minute or every 100 logged events) and always at app reactivation. */
    TransponderViewShowInfo = 5,
    TransponderViewTwitterView,
    TransponderViewPermissionsView
    
};


@property (strong, nonatomic) void (^retryBlock)(void);


@property (strong, nonatomic) UIAlertView *internetAlert;
@property (strong, nonatomic) UIView *loadingOverlay;
@property (strong, nonatomic) NSString *code;

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
@property (weak, nonatomic) IBOutlet UIWebView *linkedInWebView;
@property (assign, nonatomic) BOOL webViewFirstScreenLoaded;

@property (strong, nonatomic) UIView *loadingView;
//@property (strong, nonatomic) NSCache *cache; //image cache for profile pics





@end

@implementation TransponderViewController;
@synthesize retryBlock;
@synthesize loadingOverlay;

@synthesize linkedInWebView;
@synthesize webViewFirstScreenLoaded;

@synthesize completion;

@synthesize cancelButton;

//showInfo variables
@synthesize showInfo;
@synthesize twitterButton;


//twitter list variables
@synthesize twitterView;



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



- (void)viewDidLoad
{
    [super viewDidLoad];
 
    {
        NSString *requestStr = self.authUrlString;
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestStr] cachePolicy:NSURLCacheStorageAllowedInMemoryOnly timeoutInterval:25];
        [linkedInWebView loadRequest:request];
    }
    // Do any additional setup after loading the view from its nib.
    
    [twitterButton addTarget:self action:@selector(twitterButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    self.showInfo.tag = TransponderViewShowInfo;
    self.twitterView.tag = TransponderViewTwitterView;
    self.permissionsView.tag = TransponderViewPermissionsView;
    
    [self.twitterView setHidden:YES];
    [self.twitterView setUserInteractionEnabled:NO];
    [self.permissionsView setHidden:YES];
    [self.permissionsView setUserInteractionEnabled:NO];

    
    linkedInWebView.delegate = self;

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


//callbacks for showInfo view
-(void)twitterButtonAction:(id)sender
{

    if (!webViewFirstScreenLoaded)
    {//setup the latency overlay
        [self.view addSubview:self.loadingOverlay];
        [self setLoadingOverlayText:@"Connecting to LinkedIn"];
        [self setLoadingErrorText:@"Connection failed.  Trying again."];
        
        __weak typeof(self) weakSelf = self;
        retryBlock = ^
        {
            UILabel *error = (UILabel*)[weakSelf.loadingOverlay viewWithTag:325];
            
            [UIView animateWithDuration:0.3 animations:^
             {
                 error.alpha = 1.0f;
             }];
             
            NSString *requestStr = weakSelf.authUrlString;
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestStr] cachePolicy:NSURLCacheStorageAllowedInMemoryOnly timeoutInterval:25];
            [weakSelf.linkedInWebView loadRequest:request];
        };
        
        self.loadingOverlay.alpha = 0.0f;
        [self animateLoadingOverlay:NO];
        [twitterView setHidden:YES];//set hidden when it is not yet loaded, fade it in later
    }

    [self animateFromView:showInfo toView:twitterView];

}


-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSString *urlString = [error.userInfo objectForKey:NSErrorFailingURLStringKey];
    NSInteger code = error.code;
    NSLog(@"code = %d", code);
    //Code = -1001
    //retryBlock
    if ([urlString isEqualToString:self.authUrlString])
    {
        retryBlock();
    } else
//    if ([urlString isEqualToString:@"https://www.linkedin.com/uas/oauth2/authorizedialog/submit"])
    if (code != 102)
    {
        [self showAlertIfNotAlready];
    }
    
    NSLog(@"FAIL %@", error);
    NSLog(@"\t%@", urlString);
    NSLog(@"\t%@", self.authUrlString);
}
-(void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSURL *url = webView.request.URL;
    
    if ([url.absoluteString isEqualToString:self.authUrlString])
    {
        webViewFirstScreenLoaded = YES;
        [twitterView setHidden:NO];
        [twitterView setAlpha:1.0f];
        
        if (self.loadingOverlayIsVisible)
        {
            [self animateLoadingOverlay:YES];
        }

        NSLog(@"done first load");
        return;
    }
    NSLog(@"");
    NSLog(@"FINISH load");
    NSLog(@"\t%@", url.absoluteString);
}
-(void)webViewDidStartLoad:(UIWebView *)webView
{
    NSURL *url = webView.request.URL;
    NSLog(@"");
    NSLog(@"START load");
    NSLog(@"\t%@", url.absoluteString);
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    
    NSString *loadRequestStr = request.URL.absoluteString;
    if ([loadRequestStr rangeOfString:REDIRECTURI].location == 0)
    {
        NSLog(@"response occured!  responseUrl = %@", loadRequestStr);
        loadRequestStr = [[loadRequestStr componentsSeparatedByString:@"?"] lastObject];
        NSArray *keyValues = [loadRequestStr componentsSeparatedByString:@"&"];
        
        NSString *errorValue = nil;
        NSString *errorDescriptionValue = nil;
        for (NSString *keyValue in keyValues)
        {
            NSArray *keyAndValue = [keyValue componentsSeparatedByString:@"="];
            if (keyAndValue.count == 2)
            {
                NSString *key = [keyAndValue objectAtIndex:0];
                NSString *value = [keyAndValue objectAtIndex:1];
                
                NSLog(@"key = %@, value = %@", key, value);
                
                if ([key isEqualToString:@"code"])
                {
                    self.code = value;
                    break;
                } else
                if ([key isEqualToString:@"error"])
                {
                    errorValue = [value stringByReplacingOccurrencesOfString:@"_" withString:@" "]; //value == @"access_denied"
                } else
                if ([key isEqualToString:@"error_description"])
                {
                    errorDescriptionValue = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
                }
            }
        }
        
        if (errorValue)
        {
            NSLog(@"An error occured:");
            NSLog(@"errorValue = %@", errorValue);
            NSLog(@"errorDescription = %@", errorDescriptionValue);
            //call the completion with an error and custom error description value
            
            [self cancel:[TransponderViewController generateError:TransponderErrorCodeAuthorizationDenied withErrorDescription:errorDescriptionValue]];
            return NO;
        }
        NSLog(@"code = %@", self.code);
        
        //no double pressing buttons, dr. mr.
//        [self.linkedInWebView setUserInteractionEnabled:NO];
        
        #warning "TODO: let's put a loading view here to show what is going on"
//        [self postRequestWithLinkedInCode];
//        [self performSelector:@selector(postRequestWithLinkedInCode) withObject:nil afterDelay:22.5];
        [self postCodeToAlonso];
        
        
        return NO;
    }
    
    NSLog(@"SHOULD START \n\t%@...", request);
//    NSLog(@"\t %@", url.absoluteString);
    
    
    return YES;
}

-(void)postCodeToAlonso
{
    NSLog(@"postRequestWithLinkedInCode");
    /*
     https://www.linkedin.com/uas/oauth2/accessToken?grant_type=authorization_code
     &code=AUTHORIZATION_CODE
     &redirect_uri=YOUR_REDIRECT_URI
     &client_id=YOUR_API_KEY
     &client_secret=YOUR_SECRET_KEY
     */
    NSString *requestString = [NSString stringWithFormat:@"http://transponder.mtnlab.io/user"];
    
    NSURL *url = [NSURL URLWithString:requestString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *dict = @{@"linkedinAuthCode":self.code};
    NSString *postString = [dict JSONRepresentation];
    [request setHTTPBody:[postString dataUsingEncoding:NSASCIIStringEncoding]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul), ^{
    
        dispatch_sync(dispatch_get_main_queue(), ^    {});
        
    });
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(queue,
    ^{
       
       
       NSError *error= nil;
       NSURLResponse *response = nil;
       NSLog(@"sending request to alonsolo");
       NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
       NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
       
       
       NSLog(@"repsonse string = %@", responseString);
       
       
       NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
       int status = httpResponse.statusCode;
       NSLog(@"status = %d", status);
       
       dispatch_sync(dispatch_get_main_queue(),
         ^{
             if (status == 200)
             {
                 NSLog(@"200!!!!!!");
                 NSDictionary *response = [responseString JSONValue];
                 NSString *beaconID = [response objectForKey:@"beaconID"];
                 [self transitionToPermissionViewWithBeaconID:beaconID];
             } else
             {
                 [self showAlertIfNotAlready];
//                 NSLog(@"try again!!!!!!! you failed %d", status);
//                 [self postCodeToAlonso];
                 //wait
             }
         });
    });
}

//-(void)postRequestWithLinkedInCode
//{
//    NSLog(@"postRequestWithLinkedInCode");
//    /*
//     https://www.linkedin.com/uas/oauth2/accessToken?grant_type=authorization_code
//     &code=AUTHORIZATION_CODE
//     &redirect_uri=YOUR_REDIRECT_URI
//     &client_id=YOUR_API_KEY
//     &client_secret=YOUR_SECRET_KEY
//     */
//    NSString *requestString = [NSString stringWithFormat:@"https://www.linkedin.com/uas/oauth2/accessToken?grant_type=authorization_code&code=%@&redirect_uri=%@&client_id=%@&client_secret=%@", self.code, REDIRECTURI, API_KEY, SECRET_KEY];
//    
//    NSURL *url = [NSURL URLWithString:requestString];
//    
//    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
//    [request setURL:url];
//    [request setHTTPMethod:@"POST"];
//    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
//    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
//    
//    
//    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
//    dispatch_async(queue,
//    ^{
//        
//        
//        NSError *error= nil;
//        NSURLResponse *response = nil;
//        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
//        NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
//        
//        
//        NSLog(@"repsonse string = %@", responseString);
//        
//        
//        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
//        int status = httpResponse.statusCode;
//        NSLog(@"status = %d", status);
//        
//        dispatch_sync(dispatch_get_main_queue(),
//        ^{
//            if (status == 200)
//            {
//#warning "faked a beaconID to proceed into the next thingy"
//                NSInteger beaconID = esRandomNumberIn(0, 99999);
//                [self transitionToPermissionViewWithBeaconID:beaconID];
//            } else
//            {
//                NSAssert(NO, @"handle the case on status != 200");
//            }
//        });
//    });
//}

-(void)transitionToPermissionViewWithBeaconID:(NSString*)beaconID
{
    
    [self animateFromView:twitterView toView:permissionsView];

    
    //save transponder id
    [[NSUserDefaults standardUserDefaults] setObject:beaconID forKey:@"transponderID"];


    [[ESTransponder sharedInstance] startTransponder];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transponderHardwareFailure:) name:TransponderDisabled object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transponderHardwareSuccess:) name:TransponderEnabled object:nil];
    
}

-(void)transponderHardwareFailure:(id)sender
{
    NSLog(@"transponderHardwareFailure:%@", sender);
}
-(void)transponderHardwareSuccess:(id)sender
{
    NSLog(@"transponderHardwareSuccess:%@", sender);
    //good to go!
    [self cancel:nil];
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
\

-(void)activateBluetoothStack
{
    [[ESTransponder sharedInstance] startTransponder];
}


//async image load helper



+(NSError*)generateError:(TransponderErrorCode)errorCode
{
    return [TransponderViewController generateError:errorCode withErrorDescription:nil];
}
+(NSError*)generateError:(TransponderErrorCode)errorCode withErrorDescription:(NSString*)errorDescription
{
#warning "TODO: fill out localizedDescriptionKey, localizedRecoverySuggestionErrorKey,  localizedFailureReasonErrorKey"
    /*
     * (NSLocalizedDescriptionKey)              : A localized description of the error.
     * (NSLocalizedRecoverySuggestionErrorKey)  : A localized recovery suggestion for the error.
     * (NSLocalizedFailureReasonErrorKey)       : A localized explanation of the reason for the error.
     */
    
    NSMutableDictionary *userInfo;
    switch (errorCode)
    {
        case TransponderErrorCodeAuthorizationDenied:
        {
            userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""}];
        }
        break;
        case TransponderErrorCodeLocationDenied:
        {
            userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""}];
        }
        break;
        case TransponderErrorCodeBluetoothDenied:
        {
            userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""}];
        }
        break;
        case TransponderErrorCodeCancel:
        {
            userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey : @"",
                         NSLocalizedRecoverySuggestionErrorKey : @"",
                         NSLocalizedFailureReasonErrorKey : @""}];
        }
        break;
    }
    
    if (!userInfo)
    {
        return nil;
    }
    
    if (errorDescription)
    {
        [userInfo setObject:errorDescription forKey:NSLocalizedDescriptionKey];
    }
    
    return [NSError errorWithDomain:TransponderDomain code:errorCode userInfo:userInfo];
}


//-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
//{
//    if (tableView == twitterTableView)
//    {
//        return 1;
//    }
//    return 99999;
//}
//-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
//{
//    if (tableView == twitterTableView)
//    {
//        return 1 + self.twitterAccounts.count;
//    }
//    return 99999;
//}
//-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    if (tableView == twitterTableView)
//    {
//        TwitterCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TwitterCell"];
//        if (!cell)
//        {
//            NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"TwitterCell" owner:self options:nil];
//            // Grab a pointer to the first object (presumably the custom cell, as that's all the XIB should contain).
//            cell = [topLevelObjects objectAtIndex:0];
//            //asynchronous image loading into the appropriate cell!
//
//        }
//
//        return cell;
//    }
//    return nil;
//}
//
//-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    if (tableView == twitterTableView)
//    {
//        NSLog(@"selected profile %d", indexPath.row);
//
//        [self animateFromView:twitterView toView:permissionsView];
//
//        [self performSelector:@selector(activateBluetoothStack) withObject:nil afterDelay:1];
//
//        [tableView setUserInteractionEnabled:NO];
//    }
//}

//- (void)processImageDataWithURLString:(NSString *)urlString andBlock:(void (^)(UIImage *imageData, BOOL synchronous))processImage
//{
//
//    NSURL *url = [NSURL URLWithString:urlString];
//    UIImage *retrievedImage = [self.cache objectForKey:url];
//    if (retrievedImage)
//    {
//        processImage(retrievedImage, YES);
//    }
//
//    dispatch_queue_t callerQueue = dispatch_get_current_queue();
//    dispatch_queue_t downloadQueue = dispatch_queue_create("TransponderViewControllerTwitterImage", NULL);
//    dispatch_async(downloadQueue, ^
//    {
//        NSData * imageData = [NSData dataWithContentsOfURL:url];
//
//        dispatch_async(callerQueue, ^
//        {
//            UIImage *img = [UIImage imageWithData:imageData];
//            [cache setObject:imageData forKey:url];
//            processImage(img, NO);
//        });
//    });
////    dispatch_release(downloadQueue);
//}

//-(NSCache*)cache
//{
//    if (!cache)
//    {
//        cache = [[NSCache alloc] init];
//    }
//    return cache;
//}
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
/* NSError
 * helper method for returning error and error descriptions
 */

//twitterButtonAction
//        [twitterButton setUserInteractionEnabled:NO];
//
//    ACAccountStore *account = [[ACAccountStore alloc] init];
//    ACAccountType *accountType = [account accountTypeWithAccountTypeIdentifier:
//                                  ACAccountTypeIdentifierTwitter];
//
//    //show loading spinner?
//    [account requestAccessToAccountsWithType:accountType options:nil
//                                  completion:^(BOOL granted, NSError *error)
//    {
//        NSLog(@"error = %@", error.localizedDescription);
//
//        self.twitterAccounts = [account
//                                accountsWithAccountType:accountType];
//
//        if (granted && self.twitterAccounts.count)
//        {
//            [self performSelectorOnMainThread:@selector(animateToShowTwitterList) withObject:nil waitUntilDone:NO];
//        } else
//        {
//#warning "If using Twitter, at this point check that self.twitterAccounts.count.  If not, then create a new error type to express that the user does not have a linked twitter.  But we won't use twitter in the future so nvm.  Still... be warned."
////            if (![[NSUserDefaults standardUserDefaults] boolForKey:Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore])
////            {
//                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:Transponder_NSUserDefaultsKey_HasDeniedTwitterAccessOnceBefore];
//                [self performSelectorOnMainThread:@selector(cancel:) withObject:[TransponderViewController generateError:TransponderErrorCodeAuthorizationDenied] waitUntilDone:NO];
//                NSLog(@"not granted my twitter type thingy!");
//
////            }
//        }
//    }];

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
-(NSString*)authUrlString
{
    return [NSString stringWithFormat:@"https://www.linkedin.com/uas/oauth2/authorization?response_type=code&client_id=%@&scope=%@&state=%@&redirect_uri=%@", API_KEY, SCOPE, STATE, REDIRECTURI];
    
}
//description of what is going on
-(void)setLoadingOverlayText:(NSString*)txt
{
    UILabel *label = (UILabel*)[self.loadingOverlay viewWithTag:9585];

    label.alpha = 1.0f;
    label.text = txt;
}
-(void)setLoadingErrorText:(NSString*)text
{
    UILabel *error = (UILabel*)[self.loadingOverlay viewWithTag:325];
    
    error.alpha = 0.0f;
    error.text = text;
}
//-(void)showError
//{
//    UILabel *error = (UILabel*)[self.loadingOverlay viewWithTag:325];
//    UILabel *description = (UILabel*)[self.loadingOverlay viewWithTag:9585];
//    
//    [UIView animateWithDuration:0.3 animations:^
//    {
//        error.alpha = 1.0f;
//        description.alpha = 0.0f;
//    }];
//    
//}
-(UIView*)loadingOverlay
{
    if (!loadingOverlay)
    {
        loadingOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
        [loadingOverlay setBackgroundColor:[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.4f]];
        
        UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        CGRect tempRect = activityIndicatorView.frame;
        tempRect.origin.x = (loadingOverlay.frame.size.width-tempRect.size.width)*0.5f;
        tempRect.origin.y = (loadingOverlay.frame.size.height-tempRect.size.height)*0.5f;
        [activityIndicatorView setFrame:tempRect];
        [activityIndicatorView setHidesWhenStopped:NO];
        [activityIndicatorView startAnimating];
        [loadingOverlay addSubview:activityIndicatorView];
        
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 210, 85)];
        [label setText:@"hello world"];
        [label setNumberOfLines:0];
        [label setTextColor:[UIColor whiteColor]];
        label.tag = 9585;

//        [label setBackgroundColor:[UIColor redColor]];
        [label setTextAlignment:NSTextAlignmentCenter];
        UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Light" size:20];
        [label setFont:font];
        
        CGRect tR = label.frame;
        tR.origin.x = (loadingOverlay.frame.size.width-label.frame.size.width)*0.5f;
        tR.origin.y = (activityIndicatorView.frame.origin.y-tR.size.height)*0.5f + activityIndicatorView.frame.size.height*0.5f;
        
        [label setFrame:tR];
        
        
        
        UILabel *errorLabel = [[UILabel alloc] initWithFrame:label.frame];
        [errorLabel setTextAlignment:NSTextAlignmentCenter];
        [errorLabel setFont:font];
        [errorLabel setTextColor:[UIColor redColor] ];
        errorLabel.tag = 325;
        errorLabel.numberOfLines = 0;
        
        tR = errorLabel.frame;
        tR.origin.y += loadingOverlay.frame.size.height*0.5f;
        errorLabel.frame = tR;
        
        errorLabel.text = @"error occured";
        
        
        [loadingOverlay addSubview:errorLabel];
        [loadingOverlay addSubview:label];
        
    }
    return loadingOverlay;
}

-(BOOL)loadingOverlayIsVisible
{
    return (self.loadingOverlay.alpha == 1.0f);
}

-(void)animateLoadingOverlay:(BOOL)hidden
{
    [UIView animateWithDuration:1.3 delay:0.0f usingSpringWithDamping:1.0f initialSpringVelocity:0.0f options:UIViewAnimationOptionCurveLinear animations:^
    {
        self.loadingOverlay.alpha = (hidden ? 0.0f : 1.0f);
    } completion:^(BOOL finished)
    {
        if ( hidden )
        {
            [loadingOverlay removeFromSuperview];
        }
    }];
}
-(void)showAlertIfNotAlready
{
    if (!self.internetAlert || ![self.internetAlert isVisible])
    {
        self.internetAlert = [[UIAlertView alloc] initWithTitle:@"Oops!" message:@"We failed to receive a response, please try again." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"Okay", nil];
        [self.internetAlert show];
    }
}

//-(void)displayLoadingView
//{
//    self.loadingOverlay.alpha = 0.0f;
//    [self.view addSubview:self.loadingOverlay];
//
//    [UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^
//    {
//        self.loadingOverlay.alpha = 1.0f;
//    } completion:^(BOOL finished){}];
//}
//-(BOOL)removeLoadingOverlay
//{
//    if (loadingOverlay.superview)
//    {
//        [UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^
//        {
//            loadingOverlay.alpha = 0.0f;
//        } completion:^(BOOL finished)
//        {
//            [loadingOverlay removeFromSuperview];
//        }];
//        return YES;
//    }
//    return NO;
//}

@end
