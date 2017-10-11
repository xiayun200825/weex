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

typedef NS_ENUM(NSUInteger, WXNestedScrollSection) {
    WXNestedScrollSectionOuterTop = 0,
    WXNestedScrollSectionInner,
    WXNestedScrollSectionBottom,
};

typedef NS_ENUM(NSUInteger, WXNestedScrollArea) {
    WXNestedScrollAreaOuterView = 0,
    WXNestedScrollAreaInnerView,
};

@interface WXNestedResolver() <UIScrollViewDelegate>

@property (nonatomic, weak) UIScrollView *outerScroller;
@property (nonatomic, weak) UIScrollView *innerScroller;
@property (nonatomic, strong) NSMapTable<NSString *, WXSliderComponent *> *sliderMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSHashTable<WXNestedChildComponent *> *> *sliderGroupMap;

@property (nonatomic, weak) UIScrollView *controllingScroller;
@property (nonatomic, weak) UIScrollView *scrollingScroller;

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
    _scrollingScroller = nil;
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
    
    CGFloat controllingOffsetY = _controllingScroller.contentOffset.y;
    CGFloat outerOffsetY = (_controllingScroller == _outerScroller ? _actualOffsetY : _outerScroller.contentOffset.y);
    CGFloat innerOffsetY = (_controllingScroller == _innerScroller ? _actualOffsetY : _innerScroller.contentOffset.y);
    CGFloat currentOffsetY = outerOffsetY + innerOffsetY;
    CGFloat nextOffsetY = outerOffsetY + innerOffsetY + (_controllingScroller.contentOffset.y - _actualOffsetY);
    
    WXNestedScrollDirection direction = [self scrollDirection];
    
    WXNestedScrollSection currentSection = [self scrollSection:currentOffsetY];
    WXNestedScrollSection nextSection = [self scrollSection:nextOffsetY];
    
    WXNestedScrollArea currentArea = [self scrollArea:currentSection direction:direction];
    WXNestedScrollArea nextArea = [self scrollArea:nextSection direction:direction];
    
    if (currentArea == nextArea) {
        [self scrollToArea:currentArea offset:controllingOffsetY];
    } else {
        CGFloat dy = [self currentScrollDistance:currentOffsetY nextOffset:nextOffsetY];
        [self scrollToArea:currentArea offset:(dy + _actualOffsetY)];
        [self scrollToArea:nextArea offset:controllingOffsetY];
    }
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

- (WXNestedScrollSection)scrollSection:(CGFloat)offsetY {
    //CGFloat y0 = 0;
    CGFloat y1 = [_innerScroller convertRect:_innerScroller.bounds toView:_outerScroller].origin.y - self.offsetY;
    CGFloat y2 = y1 + _innerScroller.contentSize.height - _innerScroller.frame.size.height;
    //CGFloat y3 = _outerScroller.contentSize.height - _outerScroller.frame.size.height + (_innerScroller.contentSize.height - _innerScroller.frame.size.height);
    
    if (offsetY < y1) {
        return WXNestedScrollSectionOuterTop;
    } else if (offsetY < y2) {
        return WXNestedScrollSectionInner;
    } else {
        return WXNestedScrollSectionBottom;
    }
}

- (CGFloat)currentScrollDistance:(CGFloat)offsetY nextOffset:(CGFloat)nextOffsetY {
    CGFloat y1 = [_innerScroller convertRect:_innerScroller.bounds toView:_outerScroller].origin.y - self.offsetY;
    CGFloat y2 = y1 + _innerScroller.contentSize.height - _innerScroller.frame.size.height;
    
    if (nextOffsetY > offsetY) {
        if (offsetY <= y1 && nextOffsetY > y1) {
            return y1 - offsetY;
        } else if (offsetY <= y2 && nextOffsetY > y2) {
            return y2 - offsetY;
        }
    } else {
        if (nextOffsetY <= y1 && offsetY > y1) {
            return y1 - offsetY;
        } else if (nextOffsetY <= y2 && offsetY > y2) {
            return y2 - offsetY;
        }
    }
    return 0;
}

- (WXNestedScrollArea)scrollArea:(WXNestedScrollSection)section direction:(WXNestedScrollDirection)direction {
    if (section == WXNestedScrollSectionOuterTop) {
        return WXNestedScrollAreaOuterView;
    } else if (section == WXNestedScrollSectionInner) {
        return WXNestedScrollAreaInnerView;
    } else  {
        return WXNestedScrollAreaOuterView;
    } /*else {
       return SMScrollAreaInnerView;
       }*/
}

- (void)scrollToArea:(WXNestedScrollArea)area offset:(CGFloat)offsetY {
    [self changeScrollingView:area];
    
    if (_controllingScroller == _scrollingScroller) {
        if(offsetY - _controllingScroller.contentOffset.y <= 0.00000001) {
            _actualOffsetY = offsetY;
            return;
        }
        
        _hardCodeArea = YES;
        
        CGFloat nextOffsetY = MIN(offsetY, _scrollingScroller.contentSize.height - _scrollingScroller.frame.size.height);
        nextOffsetY = MAX(nextOffsetY, 0);
        _actualOffsetY = nextOffsetY;
        [_controllingScroller setContentOffset:CGPointMake(_controllingScroller.contentOffset.x, _actualOffsetY)];
        
        _hardCodeArea = NO;
    } else {
        _hardCodeArea = YES;
        
        CGFloat nextOffsetY = MIN(_scrollingScroller.contentOffset.y + (offsetY - _actualOffsetY), _scrollingScroller.contentSize.height - _scrollingScroller.frame.size.height);
        nextOffsetY = MAX(nextOffsetY, 0);
        [_scrollingScroller setContentOffset:CGPointMake(_scrollingScroller.contentOffset.x, nextOffsetY)];
        [_controllingScroller setContentOffset:CGPointMake(_controllingScroller.contentOffset.x, _actualOffsetY)];
        
        _hardCodeArea = NO;
    }
    
    NSLog(@"====offset inner: %f, outer: %f",_innerScroller.contentOffset.y, _outerScroller.contentOffset.y);
    
}

- (void)changeScrollingView:(WXNestedScrollArea)scrollingArea {
    UIScrollView *scrollView = nil;
    if (scrollingArea == WXNestedScrollAreaOuterView) {
        scrollView = _outerScroller;
    } else if (scrollingArea == WXNestedScrollAreaInnerView) {
        scrollView = _innerScroller;
    }
    
    if (scrollView && _scrollingScroller != scrollView) {
        _scrollingScroller = scrollView;
    }
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
