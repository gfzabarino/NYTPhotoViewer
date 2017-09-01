//
//  NYTPhotoTransitionController.m
//  NYTPhotoViewer
//
//  Created by Brian Capps on 2/13/15.
//
//

#import "NYTPhotoTransitionController.h"
#import "NYTPhotoTransitionAnimator.h"
#import "NYTPhotoDismissalInteractionController.h"

@interface NYTPhotoTransitionController ()

@property (nonatomic) NYTPhotoTransitionAnimator *animator;
@property (nonatomic) NYTPhotoDismissalInteractionController *interactionController;
@property (nonatomic, weak) UIViewController *viewController;

@end

@implementation NYTPhotoTransitionController

#pragma mark - NSObject

- (instancetype)init {
    NSAssert(NO, @"Please, use the initWithViewController: initializer");
    return [self initWithViewController:[[UIViewController alloc] init]];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];

    if (self) {
        _animator = [[NYTPhotoTransitionAnimator alloc] init];
        _interactionController = [[NYTPhotoDismissalInteractionController alloc] init];
        _forcesNonInteractiveDismissal = YES;
        _viewController = viewController;
    }

    return self;
}

#pragma mark - NYTPhotoTransitionController

- (void)didPanWithPanGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer viewToPan:(UIView *)viewToPan anchorPoint:(CGPoint)anchorPoint {
    [self.interactionController didPanWithPanGestureRecognizer:panGestureRecognizer viewToPan:viewToPan anchorPoint:anchorPoint];
}

- (UIView *)startingView {
    return self.animator.startingView;
}

- (void)setStartingView:(UIView *)startingView {
    self.animator.startingView = startingView;
}

- (UIView *)endingView {
    return self.animator.endingView;
}

- (void)setEndingView:(UIView *)endingView {
    self.animator.endingView = endingView;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    self.animator.dismissing = NO;
    BOOL changingOrientation = [UIDevice currentDevice].orientation > UIDeviceOrientationUnknown &&
            [UIDevice currentDevice].orientation <= UIDeviceOrientationLandscapeRight &&
            presenting.interfaceOrientation != (UIInterfaceOrientation)[UIDevice currentDevice].orientation;
    if (changingOrientation) {
        // we only use sourceViewForAnimating when animating orientation changes, when presenting
        // this causes a bit of flickering, but often users won't execute this scenario
        self.startingView.alpha = 0.0;
        self.animator.sourceViewForAnimating = [[self.animator class] newAnimationViewFromView:presenting.view];
        self.startingView.alpha = 1.0;
    }
    return self.animator;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    self.animator.dismissing = YES;
    self.endingView.alpha = 0.0;
    return self.animator;
}

- (id <UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id <UIViewControllerAnimatedTransitioning>)animator {
    // force non interactive if the presenter and presented view controllers have different interface orientations
    UIInterfaceOrientation presentedInterfaceOrientation = self.viewController.interfaceOrientation;
    UIInterfaceOrientation presenterInterfaceOrientation = self.viewController.presentingViewController.interfaceOrientation;
    UIView *toView = self.viewController.presentingViewController.view;
    self.animator.originalPresenterTransform = toView.transform;
    self.interactionController.originalPresenterTransform = toView.transform;
    if (self.forcesNonInteractiveDismissal ||
            (presentedInterfaceOrientation != presenterInterfaceOrientation)) {
        return nil;
    }

    self.interactionController.animator = animator;
    self.interactionController.shouldAnimateUsingAnimator = self.endingView != nil;
    self.interactionController.viewToHideWhenBeginningTransition = self.startingView ? self.endingView : nil;

    // occasionally, if we do this on the interactive transitioning's startInteractiveTransition: method,
    // the ending view is still visible on the first few frames of the interactive animation
    // setting this here fixes this issue
    self.interactionController.viewToHideWhenBeginningTransition.alpha = 0.0;

    return self.interactionController;
}

@end
