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

@property (nonatomic, copy) NSString *sliderRef;
@property (nonatomic, weak) WXComponent *slider;
@property (nonatomic, weak) UIScrollView *sliderView;
@property (nonatomic, weak) id<UIScrollViewDelegate> tmpDelegate;

@end

@implementation WXNestedChildComponent

- (void)viewDidLoad {
    [super viewDidLoad];
    [self postMessage];
}

- (void)updateAttributes:(NSDictionary *)attributes {
    [self postMessage];
}

- (void)postMessage {
    NSMutableDictionary *userInfo = [@{@"child":self,@"wxinstance":self.weexInstance} mutableCopy];
    if (self.attributes[@"slideGroup"]) {
        [userInfo setObject:self.attributes[@"slideGroup"] forKey:@"slider"];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WXNestedChildBindingNotification"
                                                        object:nil
                                                      userInfo:[userInfo copy]];
}

@end
