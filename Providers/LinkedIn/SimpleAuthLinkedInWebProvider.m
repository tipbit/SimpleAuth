//
//  SimpleAuthLinkedInProvider.m
//  SimpleAuth
//
//  Created by Abhishek Sheth on 24/01/14.
//  Copyright (c) 2014 Byliner, Inc. All rights reserved.
//

#import "SimpleAuthLinkedInWebProvider.h"
#import "SimpleAuthLinkedInWebLoginViewController.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@implementation SimpleAuthLinkedInWebProvider

#pragma mark - SimpleAuthProvider

+ (NSString *)type {
    return @"linkedin-web";
}


+ (NSDictionary *)defaultOptions {
    
    // Default present block
    SimpleAuthInterfaceHandler presentBlock = ^(UIViewController *controller) {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        navigation.modalPresentationStyle = UIModalPresentationFormSheet;
        UIViewController *presented = SimpleAuth.presentedViewController;
        [presented presentViewController:navigation animated:YES completion:nil];
    };
    
    // Default dismiss block
    SimpleAuthInterfaceHandler dismissBlock = ^(id controller) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    };
    
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:[super defaultOptions]];
    options[SimpleAuthPresentInterfaceBlockKey] = presentBlock;
    options[SimpleAuthDismissInterfaceBlockKey] = dismissBlock;
    return options;
}


- (void)authorizeWithCompletion:(SimpleAuthRequestHandler)completion {
    [[[self accessToken]
     flattenMap:^(id responseObject) {
         NSArray *signals = @[
             [self accountWithAccessToken:responseObject],
             [RACSignal return:responseObject]
         ];
         return [self rac_liftSelector:@selector(dictionaryWithAccount:accessToken:) withSignalsFromArray:signals];
     }]
     subscribeNext:^(id responseObject) {
         completion(responseObject, nil);
     }
     error:^(NSError *error) {
         completion(nil, error);
     }];
}

#pragma mark - Private

- (RACSignal *)authorizationCode {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SimpleAuthLinkedInWebLoginViewController *login0 = [[SimpleAuthLinkedInWebLoginViewController alloc] initWithOptions:self.options];
            login0.completion = ^(UIViewController *login, NSURL *URL, NSError *error) {
                SimpleAuthInterfaceHandler dismissBlock = self.options[SimpleAuthDismissInterfaceBlockKey];
                dismissBlock(login);
                
                // Parse URL
                NSString *fragment = [URL query];
                NSDictionary *dictionary = [CMDQueryStringSerialization dictionaryWithQueryString:fragment];
                NSString *code = dictionary[@"code"];
                
                // Check for error
                if (![code length]) {
                    [subscriber sendError:error];
                    return;
                }
                
                // Send completion
                [subscriber sendNext:code];
                [subscriber sendCompleted];
            };
            
            SimpleAuthInterfaceHandler block = self.options[SimpleAuthPresentInterfaceBlockKey];
            block(login0);
        });
        return nil;
    }];
}


- (RACSignal *)accessTokenWithAuthorizationCode:(NSString *)code {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"");
        
        // Build request
        NSDictionary *parameters = @{
            @"code" : code,
            @"client_id" : self.options[@"client_id"],
            @"client_secret" : self.options[@"client_secret"],
            @"redirect_uri" : self.options[@"redirect_uri"],
            @"grant_type" : @"authorization_code"
        };
        NSString *query = [CMDQueryStringSerialization queryStringWithDictionary:parameters];
        NSURL *URL = [NSURL URLWithString:@"https://api.linkedin.com/uas/oauth2/accessToken"];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:[query dataUsingEncoding:NSUTF8StringEncoding]];
        
        // Run request
        [NSURLConnection sendAsynchronousRequest:request queue:self.operationQueue
         completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
             NSLog(@"");
             NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 99)];
             NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
             if ([indexSet containsIndex:statusCode] && data) {
                 NSError *parseError = nil;
                 NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parseError];
                 if (dictionary) {
                     [subscriber sendNext:dictionary];
                     [subscriber sendCompleted];
                 }
                 else {
                     [subscriber sendError:parseError];
                 }
             }
             else {
                 [subscriber sendError:connectionError];
             }
         }];
        
        return nil;
    }];
}


- (RACSignal *)accessToken {
    return [[self authorizationCode] flattenMap:^(id responseObject) {
        return [self accessTokenWithAuthorizationCode:responseObject];
    }];
}

- (RACSignal *)accountWithAccessToken:(NSDictionary *)accessToken {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSDictionary *parameters = @{
            @"oauth2_access_token" : accessToken[@"access_token"],
            @"format" : @"json"
        };
        NSString *URLStringForProfile =  [NSString stringWithFormat:
                                @"https://api.linkedin.com/v1/people/~?%@",
                                [CMDQueryStringSerialization queryStringWithDictionary:parameters]];
        NSURL *URLProfile = [NSURL URLWithString:URLStringForProfile];
        
        NSURLRequest *requestProfile = [NSURLRequest requestWithURL:URLProfile];
        [NSURLConnection sendAsynchronousRequest:requestProfile queue:self.operationQueue
         completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
             NSLog(@"");
             NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 99)];
             NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
             if ([indexSet containsIndex:statusCode] && data) {
                 NSError *parseError = nil;
                 NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parseError];
                 if (dictionary) {
                     
                     //https://developer.linkedin.com/documents/profile-fields
                     NSString *profileFields = @"id,email-address";
                     
                     NSString *URLStringForUserId =  [NSString stringWithFormat:
                                                      @"https://api.linkedin.com/v1/people/~:(%@)?%@", profileFields,
                                                      [CMDQueryStringSerialization queryStringWithDictionary:parameters]];
                     NSURL *URLUserId = [NSURL URLWithString:URLStringForUserId];
                     NSURLRequest *requestProfile = [NSURLRequest requestWithURL:URLUserId];
                     [NSURLConnection sendAsynchronousRequest:requestProfile queue:self.operationQueue
                                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                                                NSError *parseError = nil;
                                                NSDictionary *userId = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parseError];
                                                if (!parseError && userId) {
                                                    NSMutableDictionary *dict = [dictionary mutableCopy];
                     
                                                    NSLog(@"%@", userId);
                                                    dict[@"userId"] = userId[@"id"];
                                                    dict[@"emailAddress"] = userId[@"emailAddress"];
                                                    dict[@"oauth2_access_token"] = accessToken[@"access_token"];
                                                    [subscriber sendNext:dict];
                                                    [subscriber sendCompleted];
                                                }
                                                else{
                                                    [subscriber sendError:parseError];
                                                }
                                            }];
                 }
                 else {
                     [subscriber sendError:parseError];
                 }
             }
             else {
                 [subscriber sendError:connectionError];
             }
         }];
        return nil;
    }];
}


- (NSDictionary *)dictionaryWithAccount:(NSDictionary *)account accessToken:(NSDictionary *)accessToken {
    NSLog(@"");
    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    
    // Provider
    dictionary[@"provider"] = [[self class] type];
    
    // Credentials
    NSTimeInterval expiresAtInterval = [accessToken[@"expires_in"] doubleValue];
    NSDate *expiresAtDate = [NSDate dateWithTimeIntervalSinceNow:expiresAtInterval];
    dictionary[@"credentials"] = @{
        @"token" : accessToken[@"access_token"],
        @"expires_at" : expiresAtDate,
        @"oauth2_access_token" : account[@"oauth2_access_token"]
    };
    
    // User ID
    dictionary[@"userId"] = account[@"userId"];
    dictionary[@"emailAddress"] = account[@"emailAddress"];
    
    // Raw response
    dictionary[@"raw_info"] = account;
    
    // User info
    NSMutableDictionary *user = [NSMutableDictionary new];
    user[@"first_name"] = account[@"firstName"];
    user[@"last_name"] = account[@"lastName"];
    user[@"headline"] = account[@"headline"];
    dictionary[@"user_info"] = user;
    
    return dictionary;
}

@end
