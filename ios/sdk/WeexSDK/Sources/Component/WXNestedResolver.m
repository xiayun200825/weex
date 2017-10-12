//
//  WXNestedResolver.m
//  WeexSDK
//
//  Created by xiayun on 2017/10/9.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "WXNestedResolver.h"
#import <pop/POP.h>

typedef NS_ENUM(NSUInteger, WXNestedScrollDirection) {
    WXNestedScrollDirectionUp = 0,
    WXNestedScrollDirectionDown
};

typedef struct {
    CGFloat outerOffset;
    CGFloat innerOffset;
} ScrollResult;

@interface WXNestedResolver() <UIScrollViewDelegate>

@property (nonatomic, weak) UIScrollView *outerScroller;
@property (nonatomic, weak) UIScrollView *innerScroller;
@property (nonatomic, weak) id<UIScrollViewDelegate> outerDelegate;
@property (nonatomic, weak) id<UIScrollViewDelegate> innerDelegate;
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
    
    [self restoreScrollerDelegate:_outerScroller tmpDelegate:_outerDelegate];
    [self restoreScrollerDelegate:_innerScroller tmpDelegate:_innerDelegate];
}

- (void)restoreScrollerDelegate:(UIScrollView *)scrollView tmpDelegate:(id<UIScrollViewDelegate>)tmpDelegate {
    if (scrollView) {
        if (tmpDelegate && tmpDelegate != self) {
            scrollView.delegate = tmpDelegate;
        } else {
            scrollView.delegate = nil;
        }
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
    [self restoreScrollerDelegate:_outerScroller tmpDelegate:_outerDelegate];
    [self restoreScrollerDelegate:_innerScroller tmpDelegate:_innerDelegate];
    
    _outerScroller = (UIScrollView *)_scrollParent.view;
    _innerScroller = (UIScrollView *)_scrollChild.view;
    if (_outerScroller.delegate && _outerScroller.delegate != self) {
        _outerDelegate = _outerScroller.delegate;
        _outerScroller.delegate = self;
    }
    if (_innerScroller.delegate && _innerScroller.delegate != self) {
        _innerDelegate = _innerScroller.delegate;
        _innerScroller.delegate = self;
    }
    
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
    ScrollResult result = [self getScrollResults];
    BOOL controllerForcedScroll = NO;
    
    // inner
    CGPoint offset = _innerScroller.contentOffset;
    offset.y = result.innerOffset;
    if (!CGPointEqualToPoint(offset, _innerScroller.contentOffset)) {
        [_innerScroller setContentOffset:offset];
        [_innerDelegate scrollViewDidScroll:_innerScroller];
        if (_innerScroller == _controllingScroller) {
            controllerForcedScroll = YES;
        }
    }

    // outer
    offset = _outerScroller.contentOffset;
    offset.y = result.outerOffset;
    if (!CGPointEqualToPoint(offset, _outerScroller.contentOffset)) {
        [_outerScroller setContentOffset:offset];
        [_outerDelegate scrollViewDidScroll:_outerScroller];
        if (_outerScroller == _controllingScroller) {
            controllerForcedScroll = YES;
        }
    }
    
    if (!controllerForcedScroll) {
        id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
        [delegate scrollViewDidScroll:_controllingScroller];
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
    
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [delegate scrollViewWillBeginDragging:_controllingScroller];
    }
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

- (ScrollResult)getScrollResults {
    WXNestedScrollDirection direction = [self scrollDirection];
    
    CGFloat outerOffsetY = (_controllingScroller == _outerScroller ? _actualOffsetY : _outerScroller.contentOffset.y);
    CGFloat innerOffsetY = (_controllingScroller == _innerScroller ? _actualOffsetY : _innerScroller.contentOffset.y);
    CGFloat deltaOffsetY = _controllingScroller.contentOffset.y - _actualOffsetY;
    CGRect innerRect = [_innerScroller convertRect:_innerScroller.bounds toView:_outerScroller];
    
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
            CGFloat offsetY = MIN(y1 - outerOffsetY, deltaOffsetY);
            outerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
        }
        
        // inner
        if (deltaOffsetY > 0 && innerOffsetY < y2) {
            CGFloat offsetY = MIN(y2 - innerOffsetY, deltaOffsetY);
            innerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
        }
        
        // outer bottom
        if (deltaOffsetY > 0) {
            CGFloat offsetY = (_controllingScroller == _outerScroller ? deltaOffsetY : MIN(y3 - outerOffsetY, deltaOffsetY));
            outerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
            
        }
    } else {
        CGFloat y1 = innerRect.origin.y + innerRect.size.height - _outerScroller.frame.size.height;
        CGFloat y2 = 0;
        CGFloat y3 = 0;
        
        // outer bottom
        if (outerOffsetY > y1) {
            CGFloat offsetY = MAX(y1 - outerOffsetY, deltaOffsetY);
            outerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
        }
        
        // inner
        if (deltaOffsetY < 0 && innerOffsetY > y2) {
            CGFloat offsetY = MAX(y2 - innerOffsetY, deltaOffsetY);
            innerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
        }
        
        // outer head
        if (deltaOffsetY < 0) {
            CGFloat offsetY = (_controllingScroller == _outerScroller ? deltaOffsetY : MAX(y3 - outerOffsetY, deltaOffsetY));
            outerOffsetY += offsetY;
            deltaOffsetY -= offsetY;
        }
    }
    
    ScrollResult result;
    result.innerOffset = innerOffsetY;
    result.outerOffset = outerOffsetY;
    return result;
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

#pragma mark - Other UIScrollViewDelegate
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:)]) {
        [delegate scrollViewWillEndDragging:_controllingScroller withVelocity:velocity targetContentOffset:targetContentOffset];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [delegate scrollViewDidEndDragging:_controllingScroller willDecelerate:decelerate];
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewWillBeginDecelerating:)]) {
        [delegate scrollViewWillBeginDecelerating:_controllingScroller];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)]) {
        [delegate scrollViewDidEndDecelerating:_controllingScroller];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
        [delegate scrollViewDidEndScrollingAnimation:_controllingScroller];
    }
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewShouldScrollToTop:)]) {
        return [delegate scrollViewShouldScrollToTop:_controllingScroller];
    }
    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewDidScrollToTop:)]) {
        return [delegate scrollViewDidScrollToTop:_controllingScroller];
    }
}

- (void)scrollViewDidChangeAdjustedContentInset:(UIScrollView *)scrollView {
    id<UIScrollViewDelegate> delegate = (_controllingScroller == _innerScroller ? _innerDelegate : _outerDelegate);
    if ([delegate respondsToSelector:@selector(scrollViewDidChangeAdjustedContentInset:)]) {
        if (@available(iOS 11.0, *)) {
            return [delegate scrollViewDidChangeAdjustedContentInset:_controllingScroller];
        }
    }
}

@end
