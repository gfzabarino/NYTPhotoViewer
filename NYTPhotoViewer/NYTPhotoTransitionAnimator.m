//
//  NYTPhotoTransitionAnimator.m
//  NYTPhotoViewer
//
//  Created by Brian Capps on 2/17/15.
//
//

#import "NYTPhotoTransitionAnimator.h"

static const CGFloat NYTPhotoTransitionAnimatorDurationWithZooming = 0.75;
static const CGFloat NYTPhotoTransitionAnimatorDurationWithoutZooming = 0.5;
static const CGFloat NYTPhotoTransitionAnimatorBackgroundFadeDurationRatio = 1.0;
static const CGFloat NYTPhotoTransitionAnimatorEndingViewFadeInDurationRatio = 0.1;
static const CGFloat NYTPhotoTransitionAnimatorStartingViewFadeOutDurationRatio = 0.05;
static const CGFloat NYTPhotoTransitionAnimatorSpringDamping = 0.5;

@interface NYTPhotoTransitionAnimator ()

@property (nonatomic, readonly) BOOL shouldPerformZoomingAnimation;

- (void)completeTransitionWithTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext;
- (void)animateSourceViewControllerWithContext:(id <UIViewControllerContextTransitioning>)transitionContext
                             originalTransform:(CGAffineTransform)originalTransform
                           additionalAnimation:(void (^)())additionalAnimation;
- (CGPoint)centerPointForView:(UIView *)view translatedToContainerView:(UIView *)containerView;
- (CGRect)rectForView:(UIView *)view translatedToContainerView:(UIView *)containerView;
- (NSArray<UIView *> *)closestPossibleCuttingViewsForView:(UIView *)view;
- (UIScrollView *)scrollViewFromView:(UIView *)view;
- (CGRect)visibleRectOfView:(UIView *)view inContainer:(UIView *)container;
- (NSInteger)rotationValueWithFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController;

@end

@implementation NYTPhotoTransitionAnimator

#pragma mark - NSObject

- (instancetype)init {
    self = [super init];
    
    if (self) {
        _animationDurationWithZooming = NYTPhotoTransitionAnimatorDurationWithZooming;
        _animationDurationWithoutZooming = NYTPhotoTransitionAnimatorDurationWithoutZooming;
        _animationDurationFadeRatio = NYTPhotoTransitionAnimatorBackgroundFadeDurationRatio;
        _animationDurationEndingViewFadeInRatio = NYTPhotoTransitionAnimatorEndingViewFadeInDurationRatio;
        _animationDurationStartingViewFadeOutRatio = NYTPhotoTransitionAnimatorStartingViewFadeOutDurationRatio;
        _zoomingAnimationSpringDamping = NYTPhotoTransitionAnimatorSpringDamping;
    }
    
    return self;
}

#pragma mark - NYTPhotoTransitionAnimator

- (void)setupTransitionContainerHierarchyWithTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext {
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];

    CGAffineTransform currentTransform = toView.transform;
    if (self.isDismissing && !CGAffineTransformEqualToTransform(currentTransform, self.originalPresenterTransform)) {
        // We need to temporally set this to the original value, before setting the final frame. After that we restore
        // the changed value.
        toView.transform = self.originalPresenterTransform;
    }

    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    toView.frame = [transitionContext finalFrameForViewController:toViewController];

    toView.transform = currentTransform;
    
    if (![toView isDescendantOfView:transitionContext.containerView]) {
        [transitionContext.containerView addSubview:toView];
    }

    if (self.isDismissing) {
        [transitionContext.containerView bringSubviewToFront:fromView];
    }
}

- (void)setAnimationDurationFadeRatio:(CGFloat)animationDurationFadeRatio {
    _animationDurationFadeRatio = MIN(animationDurationFadeRatio, 1.0);
}

- (void)setAnimationDurationEndingViewFadeInRatio:(CGFloat)animationDurationEndingViewFadeInRatio {
    _animationDurationEndingViewFadeInRatio = MIN(animationDurationEndingViewFadeInRatio, 1.0);
}

- (void)setAnimationDurationStartingViewFadeOutRatio:(CGFloat)animationDurationStartingViewFadeOutRatio {
    _animationDurationStartingViewFadeOutRatio = MIN(animationDurationStartingViewFadeOutRatio, 1.0);
}

#pragma mark - Fading

- (void)performFadeAnimationWithTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext {
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];

    UIView *viewToFade = toView;
    CGFloat beginningAlpha = 0.0;
    CGFloat endingAlpha = 1.0;
    
    if (self.isDismissing) {
        viewToFade = fromView;
        beginningAlpha = 1.0;
        endingAlpha = 0.0;
    }
    
    viewToFade.alpha = beginningAlpha;

    [UIView animateWithDuration:[self fadeDurationForTransitionContext:transitionContext] animations:^{
        viewToFade.alpha = endingAlpha;
    } completion:^(BOOL finished) {
        if (!self.shouldPerformZoomingAnimation) {
            [self completeTransitionWithTransitionContext:transitionContext];
        }
    }];
}

- (CGFloat)fadeDurationForTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext {
    if (self.shouldPerformZoomingAnimation) {
        return [self transitionDuration:transitionContext] * self.animationDurationFadeRatio;
    }
    
    return [self transitionDuration:transitionContext];
}

#pragma mark - Zooming

- (void)performZoomingAnimationWithTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext {
    UIView *containerView = transitionContext.containerView;
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *sourceViewControllerView = [transitionContext viewForKey:self.isDismissing ? UITransitionContextToViewKey : UITransitionContextFromViewKey];
    UIView *fullViewControllerView = [transitionContext viewForKey:self.isDismissing ? UITransitionContextFromViewKey : UITransitionContextToViewKey];
    BOOL isUsingSourceAnimatingView = NO;
    if (!self.isDismissing && UIInterfaceOrientationIsPortrait(fromViewController.interfaceOrientation) &&
            UIInterfaceOrientationIsLandscape(toViewController.interfaceOrientation)) {
        isUsingSourceAnimatingView = YES;
        sourceViewControllerView.alpha = 0.0;
        [containerView addSubview:self.sourceViewForAnimating];
        self.sourceViewForAnimating.bounds = sourceViewControllerView.bounds;
        self.sourceViewForAnimating.center = sourceViewControllerView.center;
        self.sourceViewForAnimating.transform = sourceViewControllerView.transform;
        [containerView bringSubviewToFront:toViewController.view];
    }
    CGAffineTransform startSourceViewControllerViewTransform = sourceViewControllerView.transform;
    if (self.isDismissing) {
        sourceViewControllerView.transform = self.originalPresenterTransform;
    }
    UIView *sourceView = self.isDismissing ? self.endingView : self.startingView;
    UIView *fullView = self.isDismissing ? self.startingView : self.endingView;
    UIView *containedView = [[self class] newAnimationViewFromView:sourceView];
    UIScrollView *scrollView = [self scrollViewFromView:sourceView];

    // simple way of telling what kind of rotation we have between the "from" and the "to" view controllers.
    NSInteger rotation = [self rotationValueWithFromViewController:fromViewController
                                                  toViewController:toViewController];

    // for animation purposes we will use centers, because we can safely translate them and rotate their view if
    // necessary

    __block CGSize animatingViewSourceSize;
    __block CGPoint animatingViewSourceCenter;
    __block CGRect containedViewSourceRect;
    __block CGPoint containedViewSourceMaskPosition;
    __block BOOL isAtTop;

    UIView *animatingView = [[UIView alloc] initWithFrame:CGRectZero];

    void (^calculateAnimatingViewSourceCenter)() = ^{
        NSArray *cuttingViews = [self closestPossibleCuttingViewsForView:sourceView];
        UIView *topCuttingView = [cuttingViews[0] isKindOfClass:[UIView class]] ? cuttingViews[0] : nil;
        UIView *bottomCuttingView = [cuttingViews[1] isKindOfClass:[UIView class]] ? cuttingViews[1] : nil;
        
        // this block is called in the middle of the zoom animation again, and sometimes the animating
        // view "cuts" the source view
        topCuttingView = topCuttingView == animatingView ? nil : topCuttingView;
        bottomCuttingView = bottomCuttingView == animatingView ? nil : bottomCuttingView;

        CGRect presenterViewRect = sourceViewControllerView.frame;
        CGRect sourceViewRectInContainer = [self rectForView:sourceView translatedToContainerView:containerView];
        CGRect sourceViewRect = [self rectForView:sourceView translatedToContainerView:sourceViewControllerView];
        CGRect topCuttingViewRect = [self rectForView:topCuttingView translatedToContainerView:sourceViewControllerView];
        CGRect bottomCuttingViewRect = [self rectForView:bottomCuttingView translatedToContainerView:sourceViewControllerView];
        CGRect scrollViewRect = [self rectForView:scrollView translatedToContainerView:sourceViewControllerView];

        animatingViewSourceSize = sourceViewRect.size;
        animatingViewSourceCenter = [self centerPointForView:sourceView translatedToContainerView:containerView];
        CGFloat topClippedPartHeight = 0.0;
        if (topCuttingView ||
                CGRectGetMinY(sourceViewRect) < CGRectGetMinY(presenterViewRect)) {
            CGFloat cutYOrigin = topCuttingView ? CGRectGetMaxY(topCuttingViewRect) : CGRectGetMinY(presenterViewRect);
            topClippedPartHeight = cutYOrigin - CGRectGetMinY(sourceViewRect);
            // clipped image, convert to that
            animatingViewSourceSize.height = CGRectGetMaxY(sourceViewRect) - cutYOrigin;
            CGFloat verticalDistanceFromMaxY = (CGRectGetMaxY(sourceViewRect) - cutYOrigin) / 2.0;
            if (rotation == 0 || self.isDismissing) {
                animatingViewSourceCenter.y = CGRectGetMaxY(sourceViewRectInContainer) - verticalDistanceFromMaxY;
            } else if (rotation == 1) {
                animatingViewSourceCenter.x = CGRectGetMaxX(sourceViewRectInContainer) - verticalDistanceFromMaxY;
            } else if (rotation == -1) {
                animatingViewSourceCenter.x = CGRectGetMinX(sourceViewRectInContainer) + verticalDistanceFromMaxY;
            } else if (rotation == 2) {
                animatingViewSourceCenter.y = CGRectGetMinY(sourceViewRectInContainer) + verticalDistanceFromMaxY;
            }
        } else if (bottomCuttingView ||
                CGRectGetMaxY(sourceViewRect) > CGRectGetMaxY(presenterViewRect)) {
            CGFloat cutYOrigin = bottomCuttingView ? CGRectGetMinY(bottomCuttingViewRect) : CGRectGetMaxY(presenterViewRect);
            // clipped image, convert to that
            animatingViewSourceSize.height = cutYOrigin - CGRectGetMinY(sourceViewRect);
            CGFloat verticalDistanceFromMinY = (cutYOrigin - CGRectGetMinY(sourceViewRect)) / 2.0;
            if (rotation == 0 || self.isDismissing) {
                animatingViewSourceCenter.y = CGRectGetMinY(sourceViewRectInContainer) + verticalDistanceFromMinY;
            } else if (rotation == 1) {
                animatingViewSourceCenter.x = CGRectGetMinX(sourceViewRectInContainer) + verticalDistanceFromMinY;
            } else if (rotation == -1) {
                animatingViewSourceCenter.x = CGRectGetMaxX(sourceViewRectInContainer) - verticalDistanceFromMinY;
            } else if (rotation == 2) {
                animatingViewSourceCenter.y = CGRectGetMaxY(sourceViewRectInContainer) - verticalDistanceFromMinY;
            }
        }
        isAtTop = (scrollView && CGRectGetMidY(sourceViewRect) <= CGRectGetMidY(scrollViewRect)) ||
                CGRectGetMidY(sourceViewRect) <= CGRectGetHeight(presenterViewRect) / 2.0;
        containedViewSourceRect = CGRectMake(
                0,
                -topClippedPartHeight,
                CGRectGetWidth(sourceViewRect),
                CGRectGetHeight(sourceViewRect)
        );

        if ([sourceView isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = (UIImageView *)sourceView;
            CGSize size = imageView.image.size;
            if ([fullView isKindOfClass:[UIImageView class]]) {
                ((UIImageView *)containedView).image = ((UIImageView *)fullView).image;
            }
            CGFloat originalAspectRatio = size.width / size.height;
            CGFloat targetAspectRatio = CGRectGetWidth(imageView.frame) / CGRectGetHeight(imageView.frame);
            if (originalAspectRatio < targetAspectRatio) {
                // taller
                CGFloat widthRatio = CGRectGetWidth(imageView.frame) / size.width;
                CGFloat scaledImageHeight = size.height * widthRatio;
                containedViewSourceRect.origin.y -= (scaledImageHeight - CGRectGetHeight(imageView.frame)) / 2.0;
                containedViewSourceRect.size.height = scaledImageHeight;
            } else {
                // wider
                CGFloat heightRatio = CGRectGetHeight(imageView.frame) / size.height;
                CGFloat scaledImageWidth = size.width * heightRatio;
                containedViewSourceRect.origin.x -= (scaledImageWidth - CGRectGetWidth(imageView.frame)) / 2.0;
                containedViewSourceRect.size.width = scaledImageWidth;
            }

            containedView.contentMode = UIViewContentModeScaleAspectFill;
        }

        containedViewSourceMaskPosition = CGPointMake(
                CGRectGetWidth(containedViewSourceRect) / 2.0,
                CGRectGetHeight(containedViewSourceRect) / 2.0
        );

    };
    calculateAnimatingViewSourceCenter();

    CGRect fullViewRect = [self rectForView:fullView translatedToContainerView:fullViewControllerView];

    CGRect containedViewFullRect = CGRectMake(0, 0, CGRectGetWidth(fullViewRect), CGRectGetHeight(fullViewRect));
    animatingView.clipsToBounds = YES;
    containedView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    if (self.isDismissing) {
        containedView.frame = containedViewFullRect;
        animatingView.frame = fullViewRect;
        if (!transitionContext.isInteractive) {
            // TODO: this is a hack: there seems to be an issue when calculating the center of the full size view when dismissing having different orientations. We know this always starts from the center (when not interactive), so we just set it there
            // furthermore, we also know that when the transition is interactive, the orientations are always the same (we don't allow otherwise), therefore we just set the frame since there's no rotation whatsoever
            animatingView.center = CGPointMake(CGRectGetMidX(containerView.frame), CGRectGetMidY(containerView.frame));
        }
    } else {
        containedView.frame = containedViewSourceRect;
        containedView.layer.mask.position = containedViewSourceMaskPosition;
        animatingView.frame = CGRectMake(0, 0, animatingViewSourceSize.width, animatingViewSourceSize.height);
        animatingView.center = animatingViewSourceCenter;
    }
    [animatingView addSubview:containedView];
    [containerView addSubview:animatingView];
    self.startingView.alpha = 0.0;
    self.endingView.alpha = 0.0;

    CGSize intermediateSize = fullViewRect.size;
    CGPoint intermediateCenter = CGPointMake(CGRectGetMidX(fullViewRect), CGRectGetMidY(fullViewRect));
    intermediateSize.height *= 0.975;
    intermediateSize.width *= 0.975;
    CGFloat edgeIncrease = 20.0;
    if (((rotation == 0 || self.isDismissing) && isAtTop) || (rotation == 2 && !isAtTop)) {
        intermediateCenter.y = animatingViewSourceCenter.y - animatingViewSourceSize.height / 2.0 - edgeIncrease + intermediateSize.height / 2.0;
    } else if (((rotation == 0 || self.isDismissing) && !isAtTop) || (rotation == 2 && isAtTop)) {
        intermediateCenter.y = animatingViewSourceCenter.y + animatingViewSourceSize.height / 2.0 + edgeIncrease - intermediateSize.height / 2.0;
    } else if ((rotation == -1 && isAtTop) || (rotation == 1 && !isAtTop)) {
        intermediateCenter.x = animatingViewSourceCenter.x + animatingViewSourceSize.height / 2.0 + edgeIncrease - intermediateSize.height / 2.0;
    } else if ((rotation == -1 && !isAtTop) || (rotation == 1 && isAtTop)) {
        intermediateCenter.x = animatingViewSourceCenter.x - animatingViewSourceSize.height / 2.0 - edgeIncrease + intermediateSize.height / 2.0;
    }

    CGAffineTransform animatingViewOriginalTransform = animatingView.transform;
    if (rotation == 1) {
        animatingView.transform = CGAffineTransformRotate(animatingView.transform, -M_PI_2);
    } else if (rotation == -1) {
        animatingView.transform = CGAffineTransformRotate(animatingView.transform, M_PI_2);
    } else if (rotation == 2) {
        animatingView.transform = CGAffineTransformRotate(animatingView.transform, M_PI);
    }

    CGAffineTransform originalTransform;

    if (!self.isDismissing) {
        originalTransform = sourceViewControllerView.transform;
    } else {
        originalTransform = self.originalPresenterTransform;
    }

    __block NSTimeInterval transitionDuration = [self transitionDuration:transitionContext];

    void (^applySourceViewControllerOriginalTransform)() = ^{
        sourceViewControllerView.transform = originalTransform;
        self.sourceViewForAnimating.transform = originalTransform;
    };

    if (!self.isDismissing) {
        applySourceViewControllerOriginalTransform();
    } else {
        sourceViewControllerView.transform = startSourceViewControllerViewTransform;
        self.sourceViewForAnimating.transform = startSourceViewControllerViewTransform;
    }

    [self animateSourceViewControllerWithContext:transitionContext
                               originalTransform:originalTransform
                             additionalAnimation:^{
                                 animatingView.transform = animatingViewOriginalTransform;
                             }];

    [UIView animateWithDuration:transitionDuration
                          delay:0
                        options:UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         if (self.dismissing) {
                             applySourceViewControllerOriginalTransform();
                         } else {
                             [[self class] applyZoomTransformToPresenterView:isUsingSourceAnimatingView ? self.sourceViewForAnimating : sourceViewControllerView];
                         }
                         animatingView.transform = animatingViewOriginalTransform;
                     }
                     completion:nil];

    void (^maskAnimation)(void (^)(UIView *)) = ^(void (^completion)(UIView *)) {
        UIView *maskHelpView = [[self class] newAnimationViewFromView:sourceView];
        maskHelpView.frame = containedView.frame;
        if (self.isDismissing) {
            // non masked, switch to masked
            maskHelpView.layer.mask.position = containedViewSourceMaskPosition;
            maskHelpView.alpha = 1.0;
        } else {
            // already masked, switch to non masked
            maskHelpView.layer.mask = nil;
            maskHelpView.alpha = 0.0;
        }
        maskHelpView.autoresizingMask = containedView.autoresizingMask;
        [animatingView addSubview:maskHelpView];
        [UIView animateWithDuration:transitionDuration * 0.1
                              delay:0
                            options:UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
                         animations:^{
                             if (self.isDismissing) {
                                 containedView.alpha = 0.0;
                             } else {
                                 maskHelpView.alpha = 1.0;
                             }
                         }
                         completion:^(BOOL finished) {
                             [containedView removeFromSuperview];
                             completion(maskHelpView);
                         }];
    };

    void (^zoomAnimation)(UIView *) = ^(UIView *viewToZoom) {
        [UIView animateWithDuration:transitionDuration * 0.2
                              delay:0
                            options:UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                         animations:^{
                             animatingView.bounds = CGRectMake(0, 0, intermediateSize.width, intermediateSize.height);
                             animatingView.center = intermediateCenter;
                             CGFloat horizontalInset = (CGRectGetWidth(fullViewRect) - intermediateSize.width) / 2.0;
                             CGFloat verticalInset = (CGRectGetHeight(fullViewRect) - intermediateSize.height) / 2.0;
                             viewToZoom.frame = CGRectMake(
                                     -horizontalInset / 2.0,
                                     -verticalInset / 2.0,
                                     intermediateSize.width + horizontalInset,
                                     intermediateSize.height + verticalInset
                             );
                         }
                         completion:^(BOOL finished) {
                             if (self.isDismissing) {
                                 // we need to recompute again, as in some occasions the sourceView's frame changes
                                 // after starting the dismiss animation
                                 calculateAnimatingViewSourceCenter();
                             }
                             [UIView animateWithDuration:transitionDuration * 0.8
                                                   delay:0
                                  usingSpringWithDamping:self.isDismissing ? 1.0 : self.zoomingAnimationSpringDamping
                                   initialSpringVelocity:0
                                                 options:UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                                              animations:^{
                                                  if (self.isDismissing) {
                                                    animatingView.bounds = CGRectMake(0, 0, animatingViewSourceSize.width, animatingViewSourceSize.height);
                                                    animatingView.center = animatingViewSourceCenter;
                                                  } else {
                                                    animatingView.frame = fullViewRect;
                                                    animatingView.center = CGPointMake(CGRectGetMidX(containerView.frame), CGRectGetMidY(containerView.frame));
                                                  }
                                                  viewToZoom.frame = self.isDismissing ? containedViewSourceRect : containedViewFullRect;
                                              }
                                              completion:^(BOOL finished) {
                                                  void (^finish)() = ^{
                                                      [animatingView removeFromSuperview];
                                                      sourceViewControllerView.alpha = 1.0;
                                                      [self.sourceViewForAnimating removeFromSuperview];
                                                      self.sourceViewForAnimating = nil;
                                                      self.startingView.alpha = 1.0;
                                                      self.endingView.alpha = 1.0;
                                                      [self completeTransitionWithTransitionContext:transitionContext];
                                                  };
                                                  if (self.isDismissing) {
                                                      // back to %100, so the mask animation takes 10% of the total
                                                      // animation time
                                                      transitionDuration = transitionDuration / 0.9;
                                                      maskAnimation(^(UIView *nonMaskedView) {
                                                          finish();
                                                      });
                                                  } else {
                                                      // back to normal
                                                      applySourceViewControllerOriginalTransform();
                                                      finish();
                                                  }
                                              }];
                         }];
    };

    if (containedView.layer.mask) {
        if (self.isDismissing) {
            // make the initial zoom out to be 90% of the total time, and later will we use the 10% for the fade out of
            // the animating view into the masked view
            containedView.layer.mask = nil;
            transitionDuration = transitionDuration * 0.9;
            zoomAnimation(containedView);
        } else {
            maskAnimation(^(UIView *nonMaskedView) {
                transitionDuration = transitionDuration * 0.9;
                zoomAnimation(nonMaskedView);
            });
        }
    } else {
        zoomAnimation(containedView);
    }

}

#pragma mark - Convenience

- (BOOL)shouldPerformZoomingAnimation {
    return self.startingView && self.endingView;
}

- (void)completeTransitionWithTransitionContext:(id <UIViewControllerContextTransitioning>)transitionContext {
    if (transitionContext.isInteractive) {
        if (transitionContext.transitionWasCancelled) {
            [transitionContext cancelInteractiveTransition];
        }
        else {
            [transitionContext finishInteractiveTransition];
        }
    }
    
    [transitionContext completeTransition:!transitionContext.transitionWasCancelled];

}

- (void)animateSourceViewControllerWithContext:(id <UIViewControllerContextTransitioning>)transitionContext
                             originalTransform:(CGAffineTransform)originalTransform
                           additionalAnimation:(void (^)())additionalAnimation {
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
    UIView *view = self.isDismissing ? toView : fromView;
    BOOL isUsingSourceAnimatingView = NO;
    if (!self.isDismissing && UIInterfaceOrientationIsPortrait(fromViewController.interfaceOrientation) &&
            UIInterfaceOrientationIsLandscape(toViewController.interfaceOrientation)) {
        isUsingSourceAnimatingView = YES;
    }
    [UIView animateWithDuration:[self transitionDuration:transitionContext]
                          delay:0
                        options:UIViewAnimationOptionAllowAnimatedContent | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         if (self.dismissing) {
                             view.transform = originalTransform;
                         } else {
                             [[self class] applyZoomTransformToPresenterView:isUsingSourceAnimatingView ? self.sourceViewForAnimating : view];
                         }
                         if (additionalAnimation) {
                             additionalAnimation();
                         }
                     }
                     completion:nil];
}

- (CGPoint)centerPointForView:(UIView *)view translatedToContainerView:(UIView *)containerView {
    CGPoint centerPoint = view.center;
    
    // Special case for zoomed scroll views.
    if ([view.superview isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view.superview;
        
        if (scrollView.zoomScale != 1.0) {
            centerPoint.x += (CGRectGetWidth(scrollView.bounds) - scrollView.contentSize.width) / 2.0 + scrollView.contentOffset.x;
            centerPoint.y += (CGRectGetHeight(scrollView.bounds) - scrollView.contentSize.height) / 2.0 + scrollView.contentOffset.y;
        }
    }
    
    return [view.superview convertPoint:centerPoint toView:containerView];
}

- (CGRect)rectForView:(UIView *)view translatedToContainerView:(UIView *)containerView {
    CGRect rect = view.frame;

    // Special case for zoomed scroll views.
    if ([view.superview isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view.superview;

        if (scrollView.zoomScale != 1.0) {
            rect.origin.x += (CGRectGetWidth(scrollView.bounds) - scrollView.contentSize.width) / 2.0 + scrollView.contentOffset.x;
            rect.origin.y += (CGRectGetHeight(scrollView.bounds) - scrollView.contentSize.height) / 2.0 + scrollView.contentOffset.y;
        }
    }

    return [view.superview convertRect:rect toView:containerView];
}

+ (UIView *)newAnimationViewFromView:(UIView *)view {
    if (!view) {
        return nil;
    }

    UIView *animationView;
    if (view.layer.contents) {
        // this is needed so when the photo view controller is presented and its final size is
        // different from its design size, its view gets resized to the final size.
        // If we don't do this, view frames gets wrong values, which in turn breaks the animation.
        //
        // NOTE: when view.layer.contents is nil, the snapshotViewAfterScreenUpdates call with a YES parameter
        // takes care of forcing a layout
        [view.window setNeedsLayout];
        [view.window layoutIfNeeded];

        if ([view isKindOfClass:[UIImageView class]]) {
            // The case of UIImageView is handled separately since the mere layer's contents (i.e. CGImage in this case) doesn't
            // seem to contain proper informations about the image orientation for portrait images taken directly on the device.
            // See https://github.com/NYTimes/NYTPhotoViewer/issues/115
            animationView = [(UIImageView *)[[view class] alloc] initWithImage:((UIImageView *)view).image];
            animationView.bounds = view.bounds;
        }
        else {
            animationView = [[UIView alloc] initWithFrame:view.frame];
            animationView.layer.contents = view.layer.contents;
            animationView.layer.bounds = view.layer.bounds;
        }

        animationView.layer.cornerRadius = view.layer.cornerRadius;
        animationView.layer.masksToBounds = view.layer.masksToBounds;
        if (view.layer.mask) {
            animationView.layer.mask = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:view.layer.mask]];
        }
        animationView.contentMode = view.contentMode;
        animationView.transform = view.transform;
    }
    else {
        // there appears to be a bug when calling [view snapshotViewAfterScreenUpdates:YES],
        // if the view is not in a window, the view is removed from its superview momentarily
        // the view is later restored to its original superview, but any layout constraints
        // between the view and its superview are lost. The following code fixes the issue
        // by adding back missing constraints
        UIView *originalSuperview = view.superview;
        NSMutableArray *originalConstraints = [view.superview.constraints mutableCopy];
        animationView = [view snapshotViewAfterScreenUpdates:YES];
        if (view.superview != originalSuperview) {
            [originalConstraints removeObjectsInArray:originalSuperview.constraints];
            if (originalConstraints.count) {
                [originalSuperview addSubview:view];
                [originalSuperview addConstraints:originalConstraints];
                [originalSuperview setNeedsLayout];
                [originalSuperview layoutIfNeeded];
            }
        }
    }

    return animationView;
}

+ (void)applyZoomTransformToPresenterView:(UIView *)view {
    view.transform = CGAffineTransformScale(view.transform, 0.95, 0.95);
    view.transform = CGAffineTransformTranslate(view.transform, 0.0, -CGRectGetHeight(view.frame) * 0.0125);
}

/**
 * Find top and bottom cutting views, that intersects the most at the view's vertical edges. Searches through top
 * sibling views and through higher level views that are not the container of the passed view.
 *
 * @param view the view
 * @return Array of top and bottom views. For any not found cutting view, this method will return [NSNull null] in the
 * corresponding array position instead. Order goes @[topCurringView, bottomCuttingView].
 */
- (NSArray<UIView *> *)closestPossibleCuttingViewsForView:(UIView *)view {
    CGFloat mostBottomTopIntersection = 0.0, mostTopBottomIntersection = 0.0;
    NSUInteger indexOfView = [view.superview.subviews indexOfObject:view];
    NSMutableArray *result = [@[[NSNull null], [NSNull null]] mutableCopy];
    UIView *rootView = view;
    // we need to go up to, but not including, the view that doesn't have its transform set to identity
    while (rootView.superview && CGAffineTransformIsIdentity(rootView.superview.transform)) {
        rootView = rootView.superview;
    }
    CGRect viewVisibleFrame = [self visibleRectOfView:view inContainer:rootView];
    UIView *iteratingView = view;
    while (iteratingView && ([result[0] isKindOfClass:[NSNull class]] || [result[1] isKindOfClass:[NSNull class]])) {
        for (UIView *aView in iteratingView.superview.subviews) {
            // check for sibling top view or subviews in upper levels in the hierarchy that are not the container of
            // this view
            if (aView != view && ((aView.superview == view.superview && [view.superview.subviews indexOfObject:aView] > indexOfView) ||
                    ![view isDescendantOfView:aView]) && !aView.isHidden && aView.alpha == 1.0) {
                CGRect aViewFrame = [self visibleRectOfView:aView inContainer:rootView];
                CGRect intersection = CGRectIntersection(viewVisibleFrame, aViewFrame);
                if (!(CGRectGetHeight(intersection) && CGRectGetHeight(intersection) < CGRectGetHeight(viewVisibleFrame))) { continue; }
                // the navigation bar is a special case, because even if it visibly covers content from the top of the
                // container, its frame has a 20 origin when the status bar is shown
                if (([aView isKindOfClass:[UINavigationBar class]] ||
                        (CGRectGetMinY(intersection) == CGRectGetMinY(viewVisibleFrame))) &&
                        CGRectGetMaxY(intersection) < CGRectGetMaxY(viewVisibleFrame)) {
                    if ([result[0] isKindOfClass:[NSNull class]] || CGRectGetMaxY(intersection) > mostBottomTopIntersection) {
                        mostBottomTopIntersection = CGRectGetMaxY(intersection);
                        result[0] = aView;
                    }
                } else if (CGRectGetMaxY(intersection) == CGRectGetMaxY(viewVisibleFrame) &&
                        CGRectGetMinY(intersection) > CGRectGetMinY(viewVisibleFrame)) {
                    if ([result[1] isKindOfClass:[NSNull class]] || CGRectGetMinY(intersection) < mostTopBottomIntersection) {
                        mostTopBottomIntersection = CGRectGetMinY(intersection);
                        result[1] = aView;
                    }
                }
            }
        }
        iteratingView = iteratingView.superview;
    }
    return result;
}

/**
 * This actually looks for UITableView and UICollectionView specifically. Some cells consist in UIScrollView, and that
 * might be a false positive for the intended behavior.
 * @param view
 * @return
 */
- (UIScrollView *)scrollViewFromView:(UIView *)view {
    __block UIScrollView *scrollView = nil;
    while (view && !scrollView) {
        [view.superview.subviews enumerateObjectsUsingBlock:^(__kindof UIView *obj, NSUInteger idx, BOOL *stop) {
            if ([obj isKindOfClass:[UICollectionView class]] || [obj isKindOfClass:[UITableView class]]) {
                *stop = YES;
                scrollView = obj;
            }
        }];
        view = view.superview;
    }
    return scrollView;
}

- (CGRect)visibleRectOfView:(UIView *)view inContainer:(UIView *)container {
    CGRect viewVisibleFrame = [self rectForView:view translatedToContainerView:container];
    CGFloat visibleYOrigin = MAX(CGRectGetMinY(viewVisibleFrame), 0);
    CGFloat visibleHeight = MIN(CGRectGetMaxY(viewVisibleFrame), CGRectGetHeight(container.frame)) - visibleYOrigin;
    viewVisibleFrame.origin.y = visibleYOrigin;
    viewVisibleFrame.size.height = visibleHeight;
    return viewVisibleFrame;
}

/**
 * Generates a rotation identifier based on how many 90 degrees rotations the interface makes between these two view
 * controllers. Rotating to the right has a positive sign, and rotating to the left as a negative sign. Rotating 180
 * degrees always returns a positive side.
 * @param fromViewController
 * @param toViewController
 * @return
 */
- (NSInteger)rotationValueWithFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController {
    // default to same orientation
    NSInteger rotation = 0;
    switch (fromViewController.interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            switch (toViewController.interfaceOrientation) {
                case UIInterfaceOrientationLandscapeLeft:
                    rotation = -1;
                    break;
                case UIInterfaceOrientationLandscapeRight:
                    rotation = 1;
                    break;
                case UIInterfaceOrientationPortraitUpsideDown:
                    rotation = 2;
                    break;
                default:
                    break;
            }
            break;
        case UIInterfaceOrientationLandscapeLeft:
            switch (toViewController.interfaceOrientation) {
                case UIInterfaceOrientationPortrait:
                    rotation = 1;
                    break;
                case UIInterfaceOrientationLandscapeRight:
                    rotation = 2;
                    break;
                case UIInterfaceOrientationPortraitUpsideDown:
                    rotation = -1;
                    break;
                default:
                    break;
            }
            break;
        case UIInterfaceOrientationLandscapeRight:
            switch (toViewController.interfaceOrientation) {
                case UIInterfaceOrientationPortrait:
                    rotation = -1;
                    break;
                case UIInterfaceOrientationLandscapeLeft:
                    rotation = 2;
                    break;
                case UIInterfaceOrientationPortraitUpsideDown:
                    rotation = 1;
                    break;
                default:
                    break;
            }
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            switch (toViewController.interfaceOrientation) {
                case UIInterfaceOrientationPortrait:
                    rotation = 2;
                    break;
                case UIInterfaceOrientationLandscapeLeft:
                    rotation = 1;
                    break;
                case UIInterfaceOrientationLandscapeRight:
                    rotation = -1;
                    break;
                default:
                    break;
            }
            break;
        default:
            break;
    }
    return rotation;
}

#pragma mark - UIViewControllerAnimatedTransitioning

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext {
    if (self.shouldPerformZoomingAnimation) {
        return self.animationDurationWithZooming;
    }
    
    return self.animationDurationWithoutZooming;
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext {
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];

    [self setupTransitionContainerHierarchyWithTransitionContext:transitionContext];

    [self performFadeAnimationWithTransitionContext:transitionContext];

    if (self.shouldPerformZoomingAnimation) {
        [self performZoomingAnimationWithTransitionContext:transitionContext];
    } else if (self.isDismissing) {
        UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
        if (!transitionContext.isInteractive) {
            [NYTPhotoTransitionAnimator applyZoomTransformToPresenterView:toView];
        }
        [self animateSourceViewControllerWithContext:transitionContext
                                   originalTransform:self.originalPresenterTransform
                                 additionalAnimation:nil];
    }
}

- (void)animationEnded:(BOOL)transitionCompleted {
    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
}

@end
