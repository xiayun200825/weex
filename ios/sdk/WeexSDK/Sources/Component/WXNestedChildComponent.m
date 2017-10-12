//
//  WXNestedChildComponent.m
//  WeexSDK
//
//  Created by xiayun on 2017/10/9.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "WXNestedChildComponent.h"
#import "WeexSDK.h"
#import "WXUtility.h"

@interface WXNestedChildComponent()

@end

@implementation WXNestedChildComponent

- (void)viewDidLoad {
    [super viewDidLoad];
    [self bindParent];
}

- (void)updateAttributes:(NSDictionary *)attributes {
    [self bindParent];
}

- (void)bindParent {
    NSMutableDictionary *userInfo = [@{@"child":self,@"wxinstance":self.weexInstance} mutableCopy];
    if (self.attributes[@"slideGroup"]) {
        [userInfo setObject:self.attributes[@"slideGroup"] forKey:@"slider"];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WXNestedChildBindingNotification"
                                                        object:nil
                                                      userInfo:[userInfo copy]];
}

@end
