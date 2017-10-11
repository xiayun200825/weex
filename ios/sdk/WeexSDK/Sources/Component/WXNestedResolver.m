//
//  WXNestedResolver.m
//  WeexSDK
//
//  Created by xiayun on 2017/10/9.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "WXNestedResolver.h"

typedef NS_ENUM(NSUInteger, WXNestedScrollDirection) {
    WXNestedScrollDirectionUp = 0,
    WXNestedScrollDirectionDown
};

@interface WXNestedScrollResult : NSObject

@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, assign) CGFloat offset;

+ (instancetype)scrollResult:(UIScrollView *)scrollView offset:(CGFloat)offset;

@end

@implementation WXNestedScrollResult

+ (instancetype)scrollResult:(UIScrollView *)scrollView offset:(CGFloat)offset {
    WXNestedScrollResult *result = [WXNestedScrollResult new];
    result.scrollView = scrollView;
    result.offset = offset;
    return result;
}

@end

@interface WXNestedResolver() <UIScrollViewDelegate>

@property (nonatomic, weak) UIScrollView *outerScroller;
@property (nonatomic, weak) UIScrollView *innerScroller;
@property (nonatomic, strong) NSMapTable<NSString *, WXSliderComponent *> *sliderMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSHashTable<WXNestedChildComponent *> *> *sliderGroupMap;

@property (nonatomic, weak) UIScrollView *controllingScroller;

@property (nonatomic, assign) CGFloat offsetY;
@property (nonatomic, assign) CGFloat actualOffsetY;
@property (nonatomic, assign) WXNestedScrollDirection direction;

@property (nonatomic, assign) BOOL hardCodeArea;

@end

@implementation WXNestedResolver

- (instancetype)initWithScrollParent:(WXNestedParentComponent *)parent {
    if (self = [super init]) {
        _scrollParent = parent;
        _sliderMap = [NSMapTable strongToWeakObjectsMapTable];
        _sliderGroupMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    for (NSString *ref in _sliderMap) {
        WXSliderComponent *slider = [_sliderMap objectForKey:ref];
        [slider removeObserver:self forKeyPath:@"currentIndex"];
    }
}

- (void)updateWithScrollChild:(WXNestedChildComponent *)child slider:(WXSliderComponent *)slider {
    if (!slider) {
        _scrollChild = child;
        [self setup];
        return;
    }
    
    WXSliderComponent *curSlider = [_sliderMap objectForKey:slider.ref];
    NSHashTable *childList = [_sliderGroupMap objectForKey:slider.ref];
    if (!curSlider) {
        [slider addObserver:self
                  forKeyPath:@"currentIndex"
                     options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew
                     context:nil];
        [_sliderMap setObject:slider forKey:slider.ref];
        childList = [NSHashTable weakObjectsHashTable];
        [_sliderGroupMap setObject:childList forKey:slider.ref];
    }
    [childList addObject:child];
    
    [self findScrollChild:slider];
}

- (void)findScrollChild:(WXSliderComponent *)slider {
    id indexObj, childObj;
    objc_property_t indexProp = class_getProperty([WXSliderComponent class], "currentIndex");
    if (indexProp != NULL) {
        indexObj = [slider valueForKey:@"currentIndex"];
    }
    
    objc_property_t childProp = class_getProperty([WXSliderComponent class], "childrenView");
    if (childProp != NULL) {
        childObj = [slider valueForKey:@"childrenView"];
    }
    
    UIView *currentView = nil;
    if (indexObj && childObj) {
        currentView = [(NSArray *)childObj objectAtIndex:[indexObj integerValue]];
        if (!currentView) {
            return;
        }
        
        NSHashTable *childList = [_sliderGroupMap objectForKey:slider.ref];
        for (WXNestedChildComponent *child in childList) {
            UIView *view = child.view;
            while (view && view != slider.view) {
                if (view == currentView) {
                    _scrollChild = child;
                    [self setup];
                    return;
                }
                view = view.superview;
            }
        }
    }
}

- (void)setup {
    _outerScroller = (UIScrollView *)_scrollParent.view;
    _innerScroller = (UIScrollView *)_scrollChild.view;
    _outerScroller.delegate = self;
    _innerScroller.delegate = self;
    
    [self reset];
}

- (void)reset {
    _controllingScroller = nil;
    _actualOffsetY = 0;
    _hardCodeArea = NO;
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_hardCodeArea || (_controllingScroller && scrollView != _controllingScroller)) {
        return;
    }
    
    if (!_controllingScroller) {
        _controllingScroller = scrollView;
    }
    
    _hardCodeArea = YES;
    NSArray<WXNestedScrollResult *> *scrollResults = [self getScrollResults];
    for (WXNestedScrollResult *result in scrollResults) {
        CGPoint offset = result.scrollView.contentOffset;
        offset.y += result.offset;
        [result.scrollView setContentOffset:offset];
    }
    _actualOffsetY = _controllingScroller.contentOffset.y;
    _hardCodeArea = NO;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == _outerScroller) {
        _controllingScroller = _outerScroller;
        NSLog(@"---outer start drag");
    } else if (scrollView == _innerScroller) {
        _controllingScroller = _innerScroller;
        NSLog(@"---inner start drag");
    }
    
    _actualOffsetY = _controllingScroller.contentOffset.y;
}

#pragma mark - private methods
- (WXNestedScrollDirection)scrollDirection {
    CGFloat currentOffsetY = _controllingScroller.contentOffset.y;
    if (currentOffsetY - _actualOffsetY > 0) {
        return WXNestedScrollDirectionUp;
    } else {
        return WXNestedScrollDirectionDown;
    }
}

- (NSArray<WXNestedScrollResult *> *)getScrollResults {
    NSMutableArray *results = [NSMutableArray array];
    WXNestedScrollDirection direction = [self scrollDirection];
    
    CGFloat outerOffsetY = (_controllingScroller == _outerScroller ? _actualOffsetY : _outerScroller.contentOffset.y);
    CGFloat innerOffsetY = (_controllingScroller == _innerScroller ? _actualOffsetY : _innerScroller.contentOffset.y);
    CGFloat deltaOffsetY = _controllingScroller.contentOffset.y - _actualOffsetY;
    CGRect innerRect = [_innerScroller convertRect:_innerScroller.bounds toView:_outerScroller];
    
    WXNestedScrollResult *controller = [WXNestedScrollResult scrollResult:_controllingScroller offset:-deltaOffsetY];
    [results addObject:controller];
    
    if (direction == WXNestedScrollDirectionUp) {
        CGFloat y1 = innerRect.origin.y - self.offsetY;
        CGFloat y2 = _innerScroller.contentSize.height
                        + _innerScroller.contentInset.top + _innerScroller.contentInset.bottom
                        - _innerScroller.frame.size.height;
        CGFloat y3 = _outerScroller.contentSize.height
                        + _outerScroller.contentInset.top + _outerScroller.contentInset.bottom
                        - _outerScroller.frame.size.height;
        
        // outer head
        if (outerOffsetY < y1) {
            WXNestedScrollResult *outerHead = [WXNestedScrollResult scrollResult:_outerScroller
                                                                          offset:MIN(y1 - outerOffsetY, deltaOffsetY)];
            [results addObject:outerHead];
            outerOffsetY += outerHead.offset;
            deltaOffsetY -= outerHead.offset;
        }
        
        // inner
        if (deltaOffsetY > 0 && innerOffsetY < y2) {
            WXNestedScrollResult *inner = [WXNestedScrollResult scrollResult:_innerScroller
                                                                      offset:MIN(y2 - innerOffsetY, deltaOffsetY)];
            [results addObject:inner];
            innerOffsetY += inner.offset;
            deltaOffsetY -= inner.offset;
        }
        
        // outer bottom
        if (deltaOffsetY > 0) {
            WXNestedScrollResult *outerBottom = [WXNestedScrollResult scrollResult:_outerScroller
                                                                            offset:MIN(y3 - outerOffsetY, deltaOffsetY)];
            [results addObject:outerBottom];
            outerOffsetY += outerBottom.offset;
            deltaOffsetY -= outerBottom.offset;
        }
    } else {
        CGFloat y1 = innerRect.origin.y + innerRect.size.height - _outerScroller.frame.size.height;
        CGFloat y2 = 0;
        CGFloat y3 = 0;
        
        // outer bottom
        if (outerOffsetY > y1) {
            WXNestedScrollResult *outerBottom = [WXNestedScrollResult scrollResult:_outerScroller
                                                                            offset:MAX(y1 - outerOffsetY, deltaOffsetY)];
            [results addObject:outerBottom];
            outerOffsetY += outerBottom.offset;
            deltaOffsetY -= outerBottom.offset;
        }
        
        // inner
        if (deltaOffsetY < 0 && innerOffsetY > y2) {
            WXNestedScrollResult *inner = [WXNestedScrollResult scrollResult:_innerScroller
                                                                      offset:MAX(y2 - innerOffsetY, deltaOffsetY)];
            [results addObject:inner];
            innerOffsetY += inner.offset;
            deltaOffsetY -= inner.offset;
        }
        
        // outer head
        if (deltaOffsetY < 0) {
            WXNestedScrollResult *outerHead = [WXNestedScrollResult scrollResult:_outerScroller
                                                                          offset:MAX(y3 - outerOffsetY, deltaOffsetY)];
            [results addObject:outerHead];
            outerOffsetY += outerHead.offset;
            deltaOffsetY -= outerHead.offset;
        }
    }
    
    return [results copy];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"currentIndex"]) {
        WXSliderComponent *slider = (WXSliderComponent *)object;
        [self findScrollChild:slider];
    }
}

- (CGFloat)offsetY {
    return _scrollParent.offsetY;
}

@end
