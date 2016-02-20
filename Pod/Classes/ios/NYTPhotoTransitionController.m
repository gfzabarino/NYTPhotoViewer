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
    
    return self.animator;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    self.animator.dismissing = YES;
    
    return self.animator;
}

- (id <UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id <UIViewControllerAnimatedTransitioning>)animator {
    // force non interactive if the presenter and presented view controllers have different interface orientations
    UIInterfaceOrientation presentedInterfaceOrientation = self.viewController.interfaceOrientation;
    UIInterfaceOrientation presenterInterfaceOrientation = self.viewController.presentingViewController.interfaceOrientation;
    if (self.forcesNonInteractiveDismissal ||
            (presentedInterfaceOrientation != presenterInterfaceOrientation)) {
        return nil;
    }
    
    // The interaction controller will be hiding the ending view, so we should get and set a visible version now.
    self.animator.endingViewForAnimation = [[self.animator class] newAnimationViewFromView:self.endingView];
    
    self.interactionController.animator = animator;
    self.interactionController.shouldAnimateUsingAnimator = self.endingView != nil;
    self.interactionController.viewToHideWhenBeginningTransition = self.startingView ? self.endingView : nil;
    
    return self.interactionController;
}

@end
