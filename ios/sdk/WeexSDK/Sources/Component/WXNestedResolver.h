//
//  WXNestedResolver.h
//  WeexSDK
//
//  Created by xiayun on 2017/10/9.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WXNestedParentComponent.h"
#import "WXNestedChildComponent.h"

@interface WXNestedResolver : NSObject

@property (nonatomic, weak) WXNestedParentComponent *scrollParent;
@property (nonatomic, weak) WXNestedChildComponent *scrollChild;

- (instancetype)initWithScrollParent:(WXNestedParentComponent *)parent;

- (void)updateWithScrollChild:(WXNestedChildComponent *)child
                       slider:(WXComponent *)slider;

@end
