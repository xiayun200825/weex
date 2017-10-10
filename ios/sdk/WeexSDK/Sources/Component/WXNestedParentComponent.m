//
//  WXNestedParentComponent.m
//  WeexSDK
//
//  Created by xiayun on 2017/10/9.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "WXNestedParentComponent.h"
#import "WXNestedChildComponent.h"
#import "WXNestedResolver.h"

@interface WXNestedParentComponent() <UIScrollViewDelegate>

@property (nonatomic, strong) WXNestedResolver *scrollResolver;

@end

@implementation WXNestedParentComponent

- (instancetype)initWithRef:(NSString *)ref type:(NSString *)type styles:(NSDictionary *)styles attributes:(NSDictionary *)attributes events:(NSArray *)events weexInstance:(WXSDKInstance *)weexInstance {
    if (self = [super initWithRef:ref type:type styles:styles attributes:attributes events:events weexInstance:weexInstance]) {
        [self initNestedParent];
    }
    return self;
}

- (void)initNestedParent {
    self.scrollResolver = [[WXNestedResolver alloc] initWithScrollParent:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bindChild:) name:@"WXNestedChildBindingNotification" object:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)bindChild:(NSNotification *)notification {
    WXSDKInstance *instance = notification.userInfo[@"wxinstance"];
    if (instance != self.weexInstance) {
        return;
    }
    
    WXNestedChildComponent *child = notification.userInfo[@"child"];
    if (!child) {
        return;
    }
    
    NSString *sliderRef = notification.userInfo[@"slider"];
    if (!sliderRef) {
        [self.scrollResolver updateWithScrollChild:child slider:nil];
        return;
    }
    
    __block WXComponent *scroller;
    WXPerformBlockOnComponentThread(^{
        
        scroller = [self.weexInstance componentForRef:sliderRef];
        if (!scroller) {
            WXLogInfo(@"binding slide-group ref:%@ is specified, but no scroller found", sliderRef);
            return;
        }
        
        WXPerformBlockOnMainThread(^{
            [self.scrollResolver updateWithScrollChild:child slider:scroller];
        });
    });
}

@end
