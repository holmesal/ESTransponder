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

//@property (strong, nonatomic) NSCache *cache; //image cache for profile pics





@end

@implementation TransponderViewController;

@synthesize linkedInWebView;

@synthesize completion;

@synthesize cancelButton;

//showInfo variables
@synthesize showInfo;
@synthesize twitterButton;


//twitter list variables
@synthesize twitterView;
//@synthesize cache;

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
 
    {
        NSString *requestStr = [NSString stringWithFormat:@"https://www.linkedin.com/uas/oauth2/authorization?response_type=code&client_id=%@&scope=%@&state=%@&redirect_uri=%@", API_KEY, SCOPE, STATE, REDIRECTURI];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestStr]];
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
//    twitterTableView.delegate = self;
//    twitterTableView.dataSource = self;
//    twitterTableView.contentInset = UIEdgeInsetsMake(cancelButton.frame.origin.x+cancelButton.frame.size.height+8, 0, 8, 0);
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
    [self animateToShowTwitterList];
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
}

-(void)twitterRejectButtonAction:(id)sender
{
    NSLog(@"twitterRejectButtonAction");
}

-(void)animateToShowTwitterList
{
    [self animateFromView:showInfo toView:twitterView];
}


-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSURL *url = webView.request.URL;
    
    NSLog(@"");
    NSLog(@"FAIL %@", error);
    NSLog(@"\t%@", url.absoluteString);
}
-(void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSURL *url = webView.request.URL;
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
        }
        NSLog(@"code = %@", self.code);
        
        //no double pressing buttons, dr. mr.
        [self.linkedInWebView setUserInteractionEnabled:NO];
        
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
    NSString *requestString = [NSString stringWithFormat:@"http://192.168.1.19:8080/user"];
    
    NSURL *url = [NSURL URLWithString:requestString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *dict = @{@"linkedinAuthCode":self.code};
    NSString *postString = [dict JSONRepresentation];
    [request setHTTPBody:[postString dataUsingEncoding:NSASCIIStringEncoding]];
    
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
                             } else
                             {
                                 NSLog(@"try again!!!!!!! you failed %d", status);
                             }
                         });
                   });
}

-(void)postRequestWithLinkedInCode
{
    NSLog(@"postRequestWithLinkedInCode");
    /*
     https://www.linkedin.com/uas/oauth2/accessToken?grant_type=authorization_code
     &code=AUTHORIZATION_CODE
     &redirect_uri=YOUR_REDIRECT_URI
     &client_id=YOUR_API_KEY
     &client_secret=YOUR_SECRET_KEY
     */
    NSString *requestString = [NSString stringWithFormat:@"https://www.linkedin.com/uas/oauth2/accessToken?grant_type=authorization_code&code=%@&redirect_uri=%@&client_id=%@&client_secret=%@", self.code, REDIRECTURI, API_KEY, SECRET_KEY];
    
    NSURL *url = [NSURL URLWithString:requestString];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(queue,
    ^{
        
        
        NSError *error= nil;
        NSURLResponse *response = nil;
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
                
            } else
            {
                NSAssert(NO, @"handle the case on status != 200");
            }
        });
    });
    
    
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

-(void)activateBluetoothStack
{
    [[ESTransponder sharedInstance] startTransponder];
}


//async image load helper

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

/* NSError
 * helper method for returning error and error descriptions
 */

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


@end
