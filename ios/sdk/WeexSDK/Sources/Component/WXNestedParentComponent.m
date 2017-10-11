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
#import "WXSliderComponent.h"
#import "WXCycleSliderComponent.h"
#import "WXEmbedComponent.h"

@interface WXNestedParentComponent() <UIScrollViewDelegate>

@property (nonatomic, strong) WXNestedResolver *scrollResolver;

@end

@implementation WXNestedParentComponent

- (instancetype)initWithRef:(NSString *)ref type:(NSString *)type styles:(NSDictionary *)styles attributes:(NSDictionary *)attributes events:(NSArray *)events weexInstance:(WXSDKInstance *)weexInstance {
    if (self = [super initWithRef:ref type:type styles:styles attributes:attributes events:events weexInstance:weexInstance]) {
        [self updateNestedOffset:attributes];
        [self initNestedParent];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateAttributes:(NSDictionary *)attributes {
    [self updateNestedOffset:attributes];
}

- (void)initNestedParent {
    self.scrollResolver = [[WXNestedResolver alloc] initWithScrollParent:self];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(bindChild:)
                                                 name:@"WXNestedChildBindingNotification"
                                               object:nil];
}

- (void)bindChild:(NSNotification *)notification {
    WXSDKInstance *instance = notification.userInfo[@"wxinstance"];
    if (!instance || ![self sameWeexInstance:instance]) {
        return;
    }
    
    WXNestedChildComponent *child = notification.userInfo[@"child"];
    if (!child || ![self isChildComponent:child]) {
        return;
    }
    
    NSString *sliderRef = notification.userInfo[@"slider"];
    if (!sliderRef || [WXUtility isBlankString:sliderRef]) {
        [self.scrollResolver updateWithScrollChild:child slider:nil];
        return;
    }
    
    __block WXSliderComponent *scroller;
    __weak typeof(self) welf = self;
    __weak WXSDKInstance *weakInstance = instance;
    WXPerformBlockOnComponentThread(^{
        scroller = (WXSliderComponent *)[welf findComponentByRef:sliderRef childInstance:weakInstance];
        if (!scroller || ![scroller isKindOfClass:[WXSliderComponent class]]) {
            WXLogInfo(@"binding slide-group ref:%@ is specified, but no scroller found", sliderRef);
            return;
        }
        
        WXPerformBlockOnMainThread(^{
            [welf.scrollResolver updateWithScrollChild:child slider:scroller];
        });
    });
}

- (BOOL)sameWeexInstance:(WXSDKInstance *)childInstance {
    WXSDKInstance *instance = childInstance;
    while (instance) {
        if (instance == self.weexInstance) {
            return YES;
        }
        instance = instance.parentInstance;
    }
    return NO;
}

- (BOOL)isChildComponent:(WXComponent *)child {
    if (child.weexInstance != self.weexInstance) {
        return YES;
    }
    
    WXComponent *component = child;
    while (component) {
        if (component == self) {
            return YES;
        }
        component = component.supercomponent;
    }
    return NO;
}

- (WXComponent *)findComponentByRef:(NSString *)ref childInstance:(WXSDKInstance *)childInstance {
    if (![ref containsString:@"-"]) {
        return [self.weexInstance componentForRef:ref];
    }
    
    NSArray *splits = [ref componentsSeparatedByString:@"-"];
    if (splits.count >= 2) {
        NSString *instanceId = splits[0];
        NSString *componentRef = splits[1];
        
        WXSDKInstance *instance = childInstance;
        while (instance) {
            if ([instanceId isEqualToString:instance.instanceId]) {
                return [instance componentForRef:componentRef];
            }
            if (instance == self.weexInstance) {
                break;
            }
            instance = instance.parentInstance;
        }
    }
    
    return nil;
}

- (void)updateNestedOffset:(NSDictionary *)attributes {
    if (attributes[@"offset"]) {
        self.offsetY = [attributes[@"offset"] floatValue];
    }
}

@end
