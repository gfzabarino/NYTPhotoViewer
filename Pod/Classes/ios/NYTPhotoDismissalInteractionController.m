//
//  NYTPhotoDismissalInteractionController.m
//  NYTPhotoViewer
//
//  Created by Brian Capps on 2/17/15.
//
//

#import "NYTPhotoDismissalInteractionController.h"
#import "NYTOperatingSystemCompatibilityUtility.h"

static const CGFloat NYTPhotoDismissalInteractionControllerPanDismissDistanceRatio = 50.0 / 667.0; // distance over iPhone 6 height.
static const CGFloat NYTPhotoDismissalInteractionControllerPanDismissMaximumDuration = 0.45;
static const CGFloat NYTPhotoDismissalInteractionControllerReturnToCenterVelocityAnimationRatio = 0.00007; // Arbitrary value that looked decent.

@interface NYTPhotoDismissalInteractionController ()

@property (nonatomic) id <UIViewControllerContextTransitioning> transitionContext;

@end

@implementation NYTPhotoDismissalInteractionController

#pragma mark - NYTPhotoDismissalInteractionController

- (void)didPanWithPanGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer viewToPan:(UIView *)viewToPan anchorPoint:(CGPoint)anchorPoint {
    UIView *fromView = [NYTOperatingSystemCompatibilityUtility fromViewForTransitionContext:self.transitionContext];
    CGPoint translatedPanGesturePoint = [panGestureRecognizer translationInView:fromView];
    CGPoint newCenterPoint = CGPointMake(anchorPoint.x + translatedPanGesturePoint.x, anchorPoint.y + translatedPanGesturePoint.y);
    
    // Pan the view on pace with the pan gesture.
    viewToPan.center = newCenterPoint;
    
    CGFloat verticalDelta = newCenterPoint.y - anchorPoint.y;
    
    CGFloat backgroundAlpha = [self backgroundAlphaForPanningWithVerticalDelta:verticalDelta];
    fromView.backgroundColor = [fromView.backgroundColor colorWithAlphaComponent:backgroundAlpha];
    
    if (panGestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self finishPanWithPanGestureRecognizer:panGestureRecognizer verticalDelta:verticalDelta viewToPan:viewToPan anchorPoint:anchorPoint];
    }
}

- (void)finishPanWithPanGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer verticalDelta:(CGFloat)verticalDelta viewToPan:(UIView *)viewToPan anchorPoint:(CGPoint)anchorPoint {
    UIView *fromView = [NYTOperatingSystemCompatibilityUtility fromViewForTransitionContext:self.transitionContext];
    
    // Return to center case.
    CGFloat velocityY = [panGestureRecognizer velocityInView:panGestureRecognizer.view].y;
    
    CGFloat animationDuration = (ABS(velocityY) * NYTPhotoDismissalInteractionControllerReturnToCenterVelocityAnimationRatio) + 0.2;
    UIViewAnimationOptions animationCurve = UIViewAnimationOptionCurveEaseOut;
    CGPoint finalPageViewCenterPoint = anchorPoint;
    CGFloat finalBackgroundAlpha = 1.0;
    
    CGFloat dismissDistance = NYTPhotoDismissalInteractionControllerPanDismissDistanceRatio * CGRectGetHeight(fromView.bounds);
    BOOL isDismissing = ABS(verticalDelta) > dismissDistance;
    
    BOOL didAnimateUsingAnimator = NO;
    
    if (isDismissing) {
        if (self.shouldAnimateUsingAnimator) {
            [self.animator animateTransition:self.transitionContext];
            didAnimateUsingAnimator = YES;
        }
        else {
            BOOL isPositiveDelta = verticalDelta >= 0;
            
            CGFloat modifier = isPositiveDelta ? 1 : -1;
            CGFloat finalCenterY = CGRectGetMidY(fromView.bounds) + modifier * CGRectGetHeight(fromView.bounds);
            finalPageViewCenterPoint = CGPointMake(fromView.center.x, finalCenterY);
            
            // Maintain the velocity of the pan, while easing out.
            animationDuration = ABS(finalPageViewCenterPoint.y - viewToPan.center.y) / ABS(velocityY);
            animationDuration = MIN(animationDuration, NYTPhotoDismissalInteractionControllerPanDismissMaximumDuration);
            
            animationCurve = UIViewAnimationOptionCurveEaseOut;
            finalBackgroundAlpha = 0.0;
        }
    }
    
    if (!didAnimateUsingAnimator) {
        [UIView animateWithDuration:animationDuration delay:0 options:animationCurve animations:^{
            viewToPan.center = finalPageViewCenterPoint;
            
            fromView.backgroundColor = [fromView.backgroundColor colorWithAlphaComponent:finalBackgroundAlpha];
        } completion:^(BOOL finished) {
            if (isDismissing) {
                [self.transitionContext finishInteractiveTransition];
            }
            else {
                [self.transitionContext cancelInteractiveTransition];
                
                if (![[self class] isRadar20070670Fixed]) {
                    [self fixCancellationStatusBarAppearanceBug];
                }
            }
            
            self.viewToHideWhenBeginningTransition.alpha = 1.0;
            
            [self.transitionContext completeTransition:isDismissing && !self.transitionContext.transitionWasCancelled];
            
            self.transitionContext = nil;
        }];
    }
    else {
        self.transitionContext = nil;
    }
}

- (CGFloat)backgroundAlphaForPanningWithVerticalDelta:(CGFloat)verticalDelta {
    CGFloat startingAlpha = 1.0;
    CGFloat finalAlpha = 0.1;
    CGFloat totalAvailableAlpha = startingAlpha - finalAlpha;
    
    CGFloat maximumDelta = CGRectGetHeight([NYTOperatingSystemCompatibilityUtility fromViewForTransitionContext:self.transitionContext].bounds) / 2.0; // Arbitrary value.
    CGFloat deltaAsPercentageOfMaximum = MIN(ABS(verticalDelta) / maximumDelta, 1.0);
    
    return startingAlpha - (deltaAsPercentageOfMaximum * totalAvailableAlpha);
}

#pragma mark - Bug Fix

- (void)fixCancellationStatusBarAppearanceBug {
    UIViewController *toViewController = [self.transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIViewController *fromViewController = [self.transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    
    NSString *statusBarViewControllerSelectorPart1 = @"_setPresentedSta";
    NSString *statusBarViewControllerSelectorPart2 = @"tusBarViewController:";
    SEL setStatusBarViewControllerSelector = NSSelectorFromString([statusBarViewControllerSelectorPart1 stringByAppendingString:statusBarViewControllerSelectorPart2]);
    
    if ([toViewController respondsToSelector:setStatusBarViewControllerSelector] && fromViewController.modalPresentationCapturesStatusBarAppearance) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [toViewController performSelector:setStatusBarViewControllerSelector withObject:fromViewController];
#pragma clang diagnostic pop
    }
}

+ (BOOL)isRadar20070670Fixed {
    // per @bcapps, this was fixed in iOS 8.3 but not marked as such on bugreport.apple.com
    // https://github.com/NYTimes/NYTPhotoViewer/issues/131#issue-126923817

    static BOOL isRadar20070670Fixed;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion const iOSVersion8Point3 = (NSOperatingSystemVersion) {
            .majorVersion = 8,
            .minorVersion = 3,
            .patchVersion = 0
        };

        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        if ([processInfo respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)]) {
            isRadar20070670Fixed = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:iOSVersion8Point3];
        }
        else {
            isRadar20070670Fixed = NO;
        }
    });

    return isRadar20070670Fixed;
}

#pragma mark - UIViewControllerInteractiveTransitioning

- (void)startInteractiveTransition:(id <UIViewControllerContextTransitioning>)transitionContext {
    self.transitionContext = transitionContext;

    UIView *fromView = [NYTOperatingSystemCompatibilityUtility fromViewForTransitionContext:self.transitionContext];
    UIView *toView = [NYTOperatingSystemCompatibilityUtility toViewForTransitionContext:self.transitionContext];

    toView.frame = [NYTOperatingSystemCompatibilityUtility finalFrameForToViewControllerWithTransitionContext:transitionContext];

    // when the presented view controller uses a full screen modal presentation style
    // the presenter's view is removed from the window, so we add it back before
    // transitioning
    if (![toView isDescendantOfView:transitionContext.containerView]) {
        [transitionContext.containerView addSubview:toView];
        [transitionContext.containerView bringSubviewToFront:fromView];
    }
}

@end
