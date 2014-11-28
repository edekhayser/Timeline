//
//  JTSImageViewController.m
//
//
//  Created by Jared Sinclair on 3/28/14.
//  Copyright (c) 2014 Nice Boy LLC. All rights reserved.
//

#import "JTSImageViewController.h"

#import "JTSSimpleImageDownloader.h"
#import "UIImage+JTSImageEffects.h"
#import "UIApplication+JTSImageViewController.h"

///--------------------------------------------------------------------------------------------------------------------
/// Definitions
///--------------------------------------------------------------------------------------------------------------------

// Public Constants
CGFloat const JTSImageViewController_DefaultAlphaForBackgroundDimmingOverlay = 0.66f;
CGFloat const JTSImageViewController_DefaultBackgroundBlurRadius = 2.0f;

// Private Constants
CGFloat const JTSImageViewController_MinimumBackgroundScaling = 0.94f;
CGFloat const JTSImageViewController_TargetZoomForDoubleTap = 3.0f;
CGFloat const JTSImageViewController_MaxScalingForExpandingOffscreenStyleTransition = 1.25f;
CGFloat const JTSImageViewController_TransitionAnimationDuration = 0.3f;
CGFloat const JTSImageViewController_MinimumFlickDismissalVelocity = 800.0f;

typedef struct {
    BOOL statusBarHiddenPriorToPresentation;
    UIStatusBarStyle statusBarStylePriorToPresentation;
    CGRect startingReferenceFrameForThumbnail;
    CGRect startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation;
    CGPoint startingReferenceCenterForThumbnail;
    UIInterfaceOrientation startingInterfaceOrientation;
    BOOL presentingViewControllerPresentedFromItsUnsupportedOrientation;
} JTSImageViewControllerStartingInfo;

typedef struct {
    BOOL isAnimatingAPresentationOrDismissal;
    BOOL isDismissing;
    BOOL isTransitioningFromInitialModalToInteractiveState;
    BOOL viewHasAppeared;
    BOOL isRotating;
    BOOL isPresented;
    BOOL rotationTransformIsDirty;
    BOOL imageIsFlickingAwayForDismissal;
    BOOL isDraggingImage;
    BOOL scrollViewIsAnimatingAZoom;
    BOOL imageIsBeingReadFromDisk;
    BOOL isManuallyResizingTheScrollViewFrame;
    BOOL imageDownloadFailed;
} JTSImageViewControllerFlags;

#define USE_DEBUG_SLOW_ANIMATIONS 0

///--------------------------------------------------------------------------------------------------------------------
/// Anonymous Category
///--------------------------------------------------------------------------------------------------------------------

@interface JTSImageViewController ()
<
UIScrollViewDelegate,
UITextViewDelegate,
UIViewControllerTransitioningDelegate,
UIGestureRecognizerDelegate
>

// General Info
@property (strong, nonatomic, readwrite) JTSImageInfo *imageInfo;
@property (strong, nonatomic, readwrite) UIImage *image;
@property (assign, nonatomic, readwrite) JTSImageViewControllerTransition transition;
@property (assign, nonatomic, readwrite) JTSImageViewControllerMode mode;
@property (assign, nonatomic, readwrite) JTSImageViewControllerBackgroundStyle backgroundStyle;
@property (assign, nonatomic) JTSImageViewControllerStartingInfo startingInfo;
@property (assign, nonatomic) JTSImageViewControllerFlags flags;

// Autorotation
@property (assign, nonatomic) UIInterfaceOrientation lastUsedOrientation;
@property (assign, nonatomic) CGAffineTransform currentSnapshotRotationTransform;

// Views
@property (strong, nonatomic) UIView *progressContainer;
@property (strong, nonatomic) UIView *outerContainerForScrollView;
@property (strong, nonatomic) UIView *snapshotView;
@property (strong, nonatomic) UIView *blurredSnapshotView;
@property (strong, nonatomic) UIView *blackBackdrop;
@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) UIProgressView *progressView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

// Gesture Recognizers
@property (strong, nonatomic) UITapGestureRecognizer *singleTapperPhoto;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapperPhoto;
@property (strong, nonatomic) UITapGestureRecognizer *singleTapperText;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPresserPhoto;
@property (strong, nonatomic) UIPanGestureRecognizer *panRecognizer;

// UIDynamics
@property (strong, nonatomic) UIDynamicAnimator *animator;
@property (strong, nonatomic) UIAttachmentBehavior *attachmentBehavior;
@property (assign, nonatomic) CGPoint imageDragStartingPoint;
@property (assign, nonatomic) UIOffset imageDragOffsetFromActualTranslation;
@property (assign, nonatomic) UIOffset imageDragOffsetFromImageCenter;

// Image Downloading
@property (strong, nonatomic) NSURLSessionDataTask *imageDownloadDataTask;
@property (strong, nonatomic) NSTimer *downloadProgressTimer;

@end

///--------------------------------------------------------------------------------------------------------------------
/// Implementation
///--------------------------------------------------------------------------------------------------------------------

@implementation JTSImageViewController

#pragma mark - Public

- (instancetype)initWithImageInfo:(JTSImageInfo *)imageInfo
                             mode:(JTSImageViewControllerMode)mode
                  backgroundStyle:(JTSImageViewControllerBackgroundStyle)backgroundStyle {
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imageInfo = imageInfo;
        _currentSnapshotRotationTransform = CGAffineTransformIdentity;
        _mode = mode;
        _backgroundStyle = backgroundStyle;
        if (_mode == JTSImageViewControllerMode_Image) {
            [self setupImageAndDownloadIfNecessary:imageInfo];
        }
    }
    return self;
}

- (void)showFromViewController:(UIViewController *)viewController
                    transition:(JTSImageViewControllerTransition)transition {
    
    [self setTransition:transition];
    
    _startingInfo.statusBarHiddenPriorToPresentation = [UIApplication sharedApplication].statusBarHidden;
    _startingInfo.statusBarStylePriorToPresentation = [UIApplication sharedApplication].statusBarStyle;
    
    if (self.mode == JTSImageViewControllerMode_Image) {
        if (transition == JTSImageViewControllerTransition_FromOffscreen) {
            [self showImageViewerByScalingDownFromOffscreenPositionWithViewController:viewController];
        } else {
            [self showImageViewerByExpandingFromOriginalPositionFromViewController:viewController];
        }
    } else if (self.mode == JTSImageViewControllerMode_AltText) {
        [self showAltTextFromViewController:viewController];
    }
}

- (void)dismiss:(BOOL)animated {
    
    if (_flags.isPresented == NO) {
        return;
    }
    
    _flags.isPresented = NO;
    
    if (self.mode == JTSImageViewControllerMode_AltText) {
        [self dismissByExpandingAltTextToOffscreenPosition];
    }
    else if (self.mode == JTSImageViewControllerMode_Image) {
        
        if (_flags.imageIsFlickingAwayForDismissal) {
            [self dismissByCleaningUpAfterImageWasFlickedOffscreen];
        }
        else if (self.transition == JTSImageViewControllerTransition_FromOffscreen) {
            [self dismissByExpandingImageToOffscreenPosition];
        }
        else {
            BOOL startingRectForThumbnailIsNonZero = (CGRectEqualToRect(CGRectZero, _startingInfo.startingReferenceFrameForThumbnail) == NO);
            BOOL useCollapsingThumbnailStyle = (startingRectForThumbnailIsNonZero
                                                && self.image != nil
                                                && self.transition != JTSImageViewControllerTransition_FromOffscreen);
            if (useCollapsingThumbnailStyle) {
                [self dismissByCollapsingImageBackToOriginalPosition];
            } else {
                [self dismissByExpandingImageToOffscreenPosition];
            }
        }
    }
}

#pragma mark - NSObject

- (void)dealloc {
    [_imageDownloadDataTask cancel];
    [self cancelProgressTimer];
}

#pragma mark - UIViewController

- (NSUInteger)supportedInterfaceOrientations {
    
    /*
     iOS 8 changes the behavior of autorotation when presenting a
     modal view controller whose supported orientations outnumber
     the orientations of the presenting view controller.
     
     E.g., when a portrait-only iPhone view controller presents
     JTSImageViewController while the **device** is oriented in
     landscape, on iOS 8 the modal view controller presents straight
     into landscape, whereas on iOS 7 the interface orientation
     of the presenting view controller is preserved.
     
     In my judgement the iOS 7 behavior is preferable. It also simplifies
     the rotation corrections during presentation. - August 31, 2014 JTS.
     */
    
    NSUInteger mask;
    
    if (self.flags.viewHasAppeared == NO) {
        switch ([UIApplication sharedApplication].statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                mask = UIInterfaceOrientationMaskLandscapeLeft;
                break;
            case UIInterfaceOrientationLandscapeRight:
                mask = UIInterfaceOrientationMaskLandscapeRight;
                break;
            case UIInterfaceOrientationPortrait:
                mask = UIInterfaceOrientationMaskPortrait;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                mask = UIInterfaceOrientationMaskPortraitUpsideDown;
                break;
            default:
                mask = UIInterfaceOrientationPortrait;
                break;
        }
    }
    else if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        mask = UIInterfaceOrientationMaskAll;
    } else {
        mask = UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return mask;
}

- (BOOL)shouldAutorotate {
    return (_flags.isAnimatingAPresentationOrDismissal == NO);
}

- (BOOL)prefersStatusBarHidden {
    
    if (_flags.isPresented || _flags.isTransitioningFromInitialModalToInteractiveState) {
        return YES;
    }
    
    return _startingInfo.statusBarHiddenPriorToPresentation;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
    return UIStatusBarAnimationFade;
}

- (UIModalTransitionStyle)modalTransitionStyle {
    return UIModalTransitionStyleCrossDissolve;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return _startingInfo.statusBarStylePriorToPresentation;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.mode == JTSImageViewControllerMode_Image) {
        [self viewDidLoadForImageMode];
    }
    else if (self.mode == JTSImageViewControllerMode_AltText) {
        [self viewDidLoadForAltTextMode];
    }
}

- (void)viewDidLayoutSubviews {
    [self updateLayoutsForCurrentOrientation];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.lastUsedOrientation != [UIApplication sharedApplication].statusBarOrientation) {
        self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
        _flags.rotationTransformIsDirty = YES;
        [self updateLayoutsForCurrentOrientation];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _flags.viewHasAppeared = YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self setLastUsedOrientation:toInterfaceOrientation];
    _flags.rotationTransformIsDirty = YES;
    _flags.isRotating = YES;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self cancelCurrentImageDrag:NO];
    [self updateLayoutsForCurrentOrientation];
    [self updateDimmingViewForCurrentZoomScale:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, duration * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        _flags.isRotating = NO;
    });
}

#pragma mark - Setup

- (void)setupImageAndDownloadIfNecessary:(JTSImageInfo *)imageInfo {
    if (imageInfo.image) {
        [self setImage:imageInfo.image];
    }
    else {
        
        [self setImage:imageInfo.placeholderImage];
        
        BOOL fromDisk = [imageInfo.imageURL.absoluteString hasPrefix:@"file://"];
        _flags.imageIsBeingReadFromDisk = fromDisk;
        
        __weak JTSImageViewController *weakSelf = self;
        NSURLSessionDataTask *task = [JTSSimpleImageDownloader downloadImageForURL:imageInfo.imageURL canonicalURL:imageInfo.canonicalImageURL completion:^(UIImage *image) {
            [weakSelf cancelProgressTimer];
            if (image) {
                if (weakSelf.isViewLoaded) {
                    [weakSelf updateInterfaceWithImage:image];
                } else {
                    [weakSelf setImage:image];
                }
            } else if (weakSelf.image == nil) {
                _flags.imageDownloadFailed = YES;
                if (_flags.isPresented && _flags.isAnimatingAPresentationOrDismissal == NO) {
                    [weakSelf dismiss:YES];
                }
                // If we're still presenting, at the end of presentation we'll auto dismiss.
            }
        }];
        
        [self setImageDownloadDataTask:task];
        
        [self startProgressTimer];
    }
}

- (void)viewDidLoadForImageMode {
    
    [self.view setBackgroundColor:[UIColor blackColor]];
    [self.view setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
    
    self.blackBackdrop = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -512, -512)];
    [self.blackBackdrop setBackgroundColor:[UIColor blackColor]];
    [self.blackBackdrop setAlpha:0];
    [self.view addSubview:self.blackBackdrop];
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate = self;
    self.scrollView.zoomScale = 1.0f;
    self.scrollView.maximumZoomScale = 8.0f;
    self.scrollView.scrollEnabled = NO;
    self.scrollView.isAccessibilityElement = YES;
    self.scrollView.accessibilityLabel = self.accessibilityLabel;
    self.scrollView.accessibilityHint = [self accessibilityHintZoomedOut];
    [self.view addSubview:self.scrollView];
    
    CGRect referenceFrameInWindow = [self.imageInfo.referenceView convertRect:self.imageInfo.referenceRect toView:nil];
    CGRect referenceFrameInMyView = [self.view convertRect:referenceFrameInWindow fromView:nil];
    
    self.imageView = [[UIImageView alloc] initWithFrame:referenceFrameInMyView];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.userInteractionEnabled = YES;
    self.imageView.isAccessibilityElement = NO;
    self.imageView.clipsToBounds = YES;
    
    // We'll add the image view to either the scroll view
    // or the parent view, based on the transition style
    // used in the "show" method.
    // After that transition completes, the image view will be
    // added to the scroll view.
    
    [self setupImageModeGestureRecognizers];
    
    self.progressContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 128.0f, 128.0f)];
    [self.view addSubview:self.progressContainer];
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0;
    self.progressView.tintColor = [UIColor whiteColor];
    self.progressView.trackTintColor = [UIColor darkGrayColor];
    CGRect progressFrame = self.progressView.frame;
    progressFrame.size.width = 128.0f;
    self.progressView.frame = progressFrame;
    self.progressView.center = CGPointMake(64.0f, 64.0f);
    self.progressView.alpha = 0;
    [self.progressContainer addSubview:self.progressView];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(64.0f, 64.0f);
    [self.spinner startAnimating];
    [self.progressContainer addSubview:self.spinner];
    [self.progressContainer setAlpha:0];
    
    self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:self.scrollView];
    
    if (self.image) {
        [self updateInterfaceWithImage:self.image];
    }
}

- (void)viewDidLoadForAltTextMode {
    
    [self.view setBackgroundColor:[UIColor blackColor]];
    [self.view setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
    
    self.blackBackdrop = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -512, -512)];
    [self.blackBackdrop setBackgroundColor:[UIColor blackColor]];
    [self.blackBackdrop setAlpha:0];
    [self.view addSubview:self.blackBackdrop];
    
    CGFloat outerMargin = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 80.0 : 40.0;
    
    self.textView = [[UITextView alloc] initWithFrame:CGRectInset(self.view.bounds, outerMargin, 0)];
    self.textView.delegate = self;
    self.textView.textColor = [UIColor whiteColor];
    self.textView.backgroundColor = [UIColor clearColor];
    
    UIFont *font = nil;
    if ([self.optionsDelegate respondsToSelector:@selector(fontForAltTextInImageViewer:)]) {
        font = [self.optionsDelegate fontForAltTextInImageViewer:self];
    }
    if (font == nil) {
        font = [UIFont systemFontOfSize:21];
    }
    self.textView.font = font;
    
    self.textView.text = self.imageInfo.displayableTitleAltTextSummary;
    
    UIColor *tintColor = nil;
    if ([self.optionsDelegate respondsToSelector:@selector(accentColorForAltTextInImageViewer:)]) {
        tintColor = [self.optionsDelegate accentColorForAltTextInImageViewer:self];
    }
    if (tintColor != nil) {
        self.textView.tintColor = tintColor;
    }
    
    self.textView.textAlignment = NSTextAlignmentCenter;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.textView.editable = NO;
    self.textView.dataDetectorTypes = UIDataDetectorTypeAll;
    [self.view addSubview:self.textView];
    
    [self setupTextViewTapGestureRecognizer];
}

- (void)setupImageModeGestureRecognizers {
    
    UITapGestureRecognizer *doubleTapper = nil;
    doubleTapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDoubleTapped:)];
    doubleTapper.numberOfTapsRequired = 2;
    doubleTapper.delegate = self;
    self.doubleTapperPhoto = doubleTapper;
    
    UILongPressGestureRecognizer *longPresser = [[UILongPressGestureRecognizer alloc] init];
    [longPresser addTarget:self action:@selector(imageLongPressed:)];
    longPresser.delegate = self;
    self.longPresserPhoto = longPresser;
    
    UITapGestureRecognizer *singleTapper = nil;
    singleTapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageSingleTapped:)];
    [singleTapper requireGestureRecognizerToFail:doubleTapper];
    [singleTapper requireGestureRecognizerToFail:longPresser];
    singleTapper.delegate = self;
    self.singleTapperPhoto = singleTapper;
    
    UIPanGestureRecognizer *panner = [[UIPanGestureRecognizer alloc] init];
    [panner addTarget:self action:@selector(dismissingPanGestureRecognizerPanned:)];
    [panner setDelegate:self];
    [self.scrollView addGestureRecognizer:panner];
    [self setPanRecognizer:panner];
    
    [self.view addGestureRecognizer:singleTapper];
    [self.view addGestureRecognizer:doubleTapper];
    [self.view addGestureRecognizer:longPresser];
}

- (void)setupTextViewTapGestureRecognizer {
    
    UITapGestureRecognizer *singleTapper = nil;
    singleTapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(textViewSingleTapped:)];
    [singleTapper setDelegate:self];
    self.singleTapperText = singleTapper;
    
    [self.textView addGestureRecognizer:singleTapper];
}

#pragma mark - Presentation

- (void)showImageViewerByExpandingFromOriginalPositionFromViewController:(UIViewController *)viewController {
    
    _flags.isAnimatingAPresentationOrDismissal = YES;
    [self.view setUserInteractionEnabled:NO];
    
    self.snapshotView = [self snapshotFromParentmostViewController:viewController];
    
    if (self.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
        self.blurredSnapshotView = [self blurredSnapshotFromParentmostViewController:viewController];
        [self.snapshotView addSubview:self.blurredSnapshotView];
        [self.blurredSnapshotView setAlpha:0];
    }
    
    [self.view insertSubview:self.snapshotView atIndex:0];
    
    _startingInfo.startingInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    
    self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
    CGRect referenceFrameInWindow = [self.imageInfo.referenceView convertRect:self.imageInfo.referenceRect toView:nil];
    
    _startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation = [self.view convertRect:referenceFrameInWindow fromView:nil];
    
    if (self.imageInfo.contentMode) {
        self.imageView.contentMode = self.imageInfo.contentMode;
    }
    
    // This will be moved into the scroll view after
    // the transition finishes.
    [self.view addSubview:self.imageView];
    
    [viewController presentViewController:self animated:NO completion:^{
        
        if ([UIApplication sharedApplication].statusBarOrientation != _startingInfo.startingInterfaceOrientation) {
            _startingInfo.presentingViewControllerPresentedFromItsUnsupportedOrientation = YES;
        }
        
        
        CGRect referenceFrameInMyView = [self.view convertRect:referenceFrameInWindow fromView:nil];
        _startingInfo.startingReferenceFrameForThumbnail = referenceFrameInMyView;
        [self.imageView setFrame:referenceFrameInMyView];
        [self updateScrollViewAndImageViewForCurrentMetrics];
        
        BOOL mustRotateDuringTransition = ([UIApplication sharedApplication].statusBarOrientation != _startingInfo.startingInterfaceOrientation);
        if (mustRotateDuringTransition) {
            CGRect newStartingRect = [self.snapshotView convertRect:_startingInfo.startingReferenceFrameForThumbnail toView:self.view];
            [self.imageView setFrame:newStartingRect];
            [self updateScrollViewAndImageViewForCurrentMetrics];
            self.imageView.transform = self.snapshotView.transform;
            CGPoint centerInRect = CGPointMake(_startingInfo.startingReferenceFrameForThumbnail.origin.x
                                               +_startingInfo.startingReferenceFrameForThumbnail.size.width/2.0f,
                                               _startingInfo.startingReferenceFrameForThumbnail.origin.y
                                               +_startingInfo.startingReferenceFrameForThumbnail.size.height/2.0f);
            [self.imageView setCenter:centerInRect];
        }
        
        if ([self.optionsDelegate respondsToSelector:@selector(imageViewerShouldFadeThumbnailsDuringPresentationAndDismissal:)]) {
            if ([self.optionsDelegate imageViewerShouldFadeThumbnailsDuringPresentationAndDismissal:self]) {
                [self.imageView setAlpha:0];
                [UIView animateWithDuration:0.15f animations:^{
                    [self.imageView setAlpha:1];
                }];
            }
        }
        
        CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
        if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
            duration *= 4;
        }
        
        __weak JTSImageViewController *weakSelf = self;
        
        // Have to dispatch ahead two runloops,
        // or else the image view changes above won't be
        // committed prior to the animations below.
        //
        // Dispatching only one runloop ahead doesn't fix
        // the issue on certain devices.
        //
        // This issue also seems to be triggered by only
        // certain kinds of interactions with certain views,
        // especially when a UIButton is the reference
        // for the JTSImageInfo.
        //
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [UIView
                 animateWithDuration:duration
                 delay:0
                 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                 animations:^{
                     
                     _flags.isTransitioningFromInitialModalToInteractiveState = YES;
                     
                     if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
                         [weakSelf setNeedsStatusBarAppearanceUpdate];
                     } else {
                         [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
                     }
                     
                     CGFloat scaling = JTSImageViewController_MinimumBackgroundScaling;
                     weakSelf.snapshotView.transform = CGAffineTransformConcat(weakSelf.snapshotView.transform, CGAffineTransformMakeScale(scaling, scaling));
                     
                     if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
                         [weakSelf.blurredSnapshotView setAlpha:1];
                     }
                     
                     [weakSelf addMotionEffectsToSnapshotView];
                     [weakSelf.blackBackdrop setAlpha:self.alphaForBackgroundDimmingOverlay];
                     
                     if (mustRotateDuringTransition) {
                         [weakSelf.imageView setTransform:CGAffineTransformIdentity];
                     }
                     
                     CGRect endFrameForImageView;
                     if (weakSelf.image) {
                         endFrameForImageView = [weakSelf resizedFrameForAutorotatingImageView:weakSelf.image.size];
                     } else {
                         endFrameForImageView = [weakSelf resizedFrameForAutorotatingImageView:weakSelf.imageInfo.referenceRect.size];
                     }
                     [weakSelf.imageView setFrame:endFrameForImageView];
                     
                     CGPoint endCenterForImageView = CGPointMake(weakSelf.view.bounds.size.width/2.0f, weakSelf.view.bounds.size.height/2.0f);
                     [weakSelf.imageView setCenter:endCenterForImageView];
                     
                     if (weakSelf.image == nil) {
                         [weakSelf.progressContainer setAlpha:1.0f];
                     }
                     
                 } completion:^(BOOL finished) {
                     
                     _flags.isManuallyResizingTheScrollViewFrame = YES;
                     [weakSelf.scrollView setFrame:weakSelf.view.bounds];
                     _flags.isManuallyResizingTheScrollViewFrame = NO;
                     [weakSelf.scrollView addSubview:weakSelf.imageView];
                     
                     _flags.isTransitioningFromInitialModalToInteractiveState = NO;
                     _flags.isAnimatingAPresentationOrDismissal = NO;
                     _flags.isPresented = YES;
                     
                     [weakSelf updateScrollViewAndImageViewForCurrentMetrics];
                     
                     if (_flags.imageDownloadFailed) {
                         [weakSelf dismiss:YES];
                     } else {
                         [weakSelf.view setUserInteractionEnabled:YES];
                     }
                 }];
            });
        });
    }];
}

- (void)showImageViewerByScalingDownFromOffscreenPositionWithViewController:(UIViewController *)viewController {
    
    _flags.isAnimatingAPresentationOrDismissal = YES;
    [self.view setUserInteractionEnabled:NO];
    
    self.snapshotView = [self snapshotFromParentmostViewController:viewController];
    
    if (self.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
        self.blurredSnapshotView = [self blurredSnapshotFromParentmostViewController:viewController];
        [self.snapshotView addSubview:self.blurredSnapshotView];
        [self.blurredSnapshotView setAlpha:0];
    }
    
    [self.view insertSubview:self.snapshotView atIndex:0];
    _startingInfo.startingInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    [self setLastUsedOrientation:[UIApplication sharedApplication].statusBarOrientation];
    CGRect referenceFrameInWindow = [self.imageInfo.referenceView convertRect:self.imageInfo.referenceRect toView:nil];
    _startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation = [self.view convertRect:referenceFrameInWindow fromView:nil];
    
    [self.scrollView addSubview:self.imageView];
    
    [viewController presentViewController:self animated:NO completion:^{
        
        if ([UIApplication sharedApplication].statusBarOrientation != _startingInfo.startingInterfaceOrientation) {
            _startingInfo.presentingViewControllerPresentedFromItsUnsupportedOrientation = YES;
        }
        
        [self.scrollView setAlpha:0];
        [self.scrollView setFrame:self.view.bounds];
        [self updateScrollViewAndImageViewForCurrentMetrics];
        CGFloat scaling = JTSImageViewController_MaxScalingForExpandingOffscreenStyleTransition;
        [self.scrollView setTransform:CGAffineTransformMakeScale(scaling, scaling)];
        
        CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
        if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
            duration *= 4;
        }
        
        __weak JTSImageViewController *weakSelf = self;
        
        // Have to dispatch to the next runloop,
        // or else the image view changes above won't be
        // committed prior to the animations below.
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [UIView
             animateWithDuration:duration
             delay:0
             options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
             animations:^{
                 
                 _flags.isTransitioningFromInitialModalToInteractiveState = YES;
                 
                 if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
                     [weakSelf setNeedsStatusBarAppearanceUpdate];
                 } else {
                     [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
                 }
                 
                 CGFloat scaling = JTSImageViewController_MinimumBackgroundScaling;
                 weakSelf.snapshotView.transform = CGAffineTransformConcat(weakSelf.snapshotView.transform, CGAffineTransformMakeScale(scaling, scaling));
                 
                 if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
                     [weakSelf.blurredSnapshotView setAlpha:1];
                 }
                 
                 [weakSelf addMotionEffectsToSnapshotView];
                 [weakSelf.blackBackdrop setAlpha:self.alphaForBackgroundDimmingOverlay];
                 
                 [weakSelf.scrollView setAlpha:1.0f];
                 [weakSelf.scrollView setTransform:CGAffineTransformIdentity];
                 
                 if (weakSelf.image == nil) {
                     [weakSelf.progressContainer setAlpha:1.0f];
                 }
                 
             } completion:^(BOOL finished) {
                 _flags.isTransitioningFromInitialModalToInteractiveState = NO;
                 _flags.isAnimatingAPresentationOrDismissal = NO;
                 [weakSelf.view setUserInteractionEnabled:YES];
                 _flags.isPresented = YES;
                 if (_flags.imageDownloadFailed) {
                     [weakSelf dismiss:YES];
                 }
             }];
        });
    }];
}

- (void)showAltTextFromViewController:(UIViewController *)viewController {
    
    _flags.isAnimatingAPresentationOrDismissal = YES;
    [self.view setUserInteractionEnabled:NO];
    
    self.snapshotView = [self snapshotFromParentmostViewController:viewController];
    
    if (self.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
        self.blurredSnapshotView = [self blurredSnapshotFromParentmostViewController:viewController];
        [self.snapshotView addSubview:self.blurredSnapshotView];
        [self.blurredSnapshotView setAlpha:0];
    }
    
    [self.view insertSubview:self.snapshotView atIndex:0];
    _startingInfo.startingInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    self.lastUsedOrientation = [UIApplication sharedApplication].statusBarOrientation;
    CGRect referenceFrameInWindow = [self.imageInfo.referenceView convertRect:self.imageInfo.referenceRect toView:nil];
    _startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation = [self.view convertRect:referenceFrameInWindow fromView:nil];
    
    __weak JTSImageViewController *weakSelf = self;
    
    [viewController presentViewController:weakSelf animated:NO completion:^{
        
        if ([UIApplication sharedApplication].statusBarOrientation != _startingInfo.startingInterfaceOrientation) {
            _startingInfo.presentingViewControllerPresentedFromItsUnsupportedOrientation = YES;
        }
        
        // Replace the text view with a snapshot of itself,
        // to prevent the text from reflowing during the dismissal animation.
        [weakSelf verticallyCenterTextInTextView];
        UIView *textViewSnapshot = [weakSelf.textView snapshotViewAfterScreenUpdates:YES];
        [textViewSnapshot setFrame:weakSelf.textView.frame];
        [weakSelf.textView.superview insertSubview:textViewSnapshot aboveSubview:self.textView];
        [weakSelf.textView setHidden:YES];
        
        [textViewSnapshot setAlpha:0];
        CGFloat scaling = JTSImageViewController_MaxScalingForExpandingOffscreenStyleTransition;
        [textViewSnapshot setTransform:CGAffineTransformMakeScale(scaling, scaling)];
        
        CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
        if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
            duration *= 4;
        }
        
        // Have to dispatch to the next runloop,
        // or else the image view changes above won't be
        // committed prior to the animations below.
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [UIView
             animateWithDuration:duration
             delay:0
             options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
             animations:^{
                 
                 _flags.isTransitioningFromInitialModalToInteractiveState = YES;
                 
                 if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
                     [weakSelf setNeedsStatusBarAppearanceUpdate];
                 } else {
                     [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
                 }
                 
                 CGFloat scaling = JTSImageViewController_MinimumBackgroundScaling;
                 weakSelf.snapshotView.transform = CGAffineTransformConcat(weakSelf.snapshotView.transform, CGAffineTransformMakeScale(scaling, scaling));
                 
                 if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
                     [weakSelf.blurredSnapshotView setAlpha:1];
                 }
                 
                 [weakSelf addMotionEffectsToSnapshotView];
                 [weakSelf.blackBackdrop setAlpha:self.alphaForBackgroundDimmingOverlay];
                 
                 [textViewSnapshot setAlpha:1.0];
                 [textViewSnapshot setTransform:CGAffineTransformIdentity];
                 
             } completion:^(BOOL finished) {
                 
                 [textViewSnapshot removeFromSuperview];
                 [weakSelf.textView setHidden:NO];
                 
                 _flags.isTransitioningFromInitialModalToInteractiveState = NO;
                 _flags.isAnimatingAPresentationOrDismissal = NO;
                 [weakSelf.view setUserInteractionEnabled:YES];
                 _flags.isPresented = YES;
             }];
        });
    }];
}

#pragma mark - Options Delegate Convenience

- (CGFloat)alphaForBackgroundDimmingOverlay {
    
    CGFloat alpha;
    
    if ([self.optionsDelegate respondsToSelector:@selector(alphaForBackgroundDimmingOverlayInImageViewer:)]) {
        alpha = [self.optionsDelegate alphaForBackgroundDimmingOverlayInImageViewer:self];
    } else {
        alpha = JTSImageViewController_DefaultAlphaForBackgroundDimmingOverlay;
    }
    
    return alpha;
}

- (CGFloat)backgroundBlurRadius {
    
    CGFloat blurRadius;
    
    if ([self.optionsDelegate respondsToSelector:@selector(backgroundBlurRadiusForImageViewer:)]) {
        blurRadius = [self.optionsDelegate backgroundBlurRadiusForImageViewer:self];
    } else {
        blurRadius = JTSImageViewController_DefaultBackgroundBlurRadius;
    }
    
    return blurRadius;
}

- (UIColor *)backgroundColorForImageView {
    
    UIColor *backgroundColor;
    
    if ([self.optionsDelegate respondsToSelector:@selector(backgroundColorImageViewInImageViewer:)]) {
        backgroundColor = [self.optionsDelegate backgroundColorImageViewInImageViewer:self];
    } else {
        backgroundColor = [UIColor clearColor];
    }
    
    return backgroundColor;
}

#pragma mark - Dismissal

- (void)dismissByCollapsingImageBackToOriginalPosition {
    
    [self.view setUserInteractionEnabled:NO];
    _flags.isAnimatingAPresentationOrDismissal = YES;
    _flags.isDismissing = YES;
    
    if ([self.optionsDelegate respondsToSelector:@selector(imageViewerShouldFadeThumbnailsDuringPresentationAndDismissal:)]) {
        if ([self.optionsDelegate imageViewerShouldFadeThumbnailsDuringPresentationAndDismissal:self]) {
            [UIView animateWithDuration:0.15 delay:0.18 options:0 animations:^{
                [self.imageView setAlpha:0];
            } completion:nil];
        }
    }
    
    CGRect imageFrame = [self.view convertRect:self.imageView.frame fromView:self.scrollView];
    self.imageView.autoresizingMask = UIViewAutoresizingNone;
    [self.imageView setTransform:CGAffineTransformIdentity];
    [self.imageView.layer setTransform:CATransform3DIdentity];
    [self.imageView removeFromSuperview];
    [self.imageView setFrame:imageFrame];
    [self.view addSubview:self.imageView];
    [self.scrollView removeFromSuperview];
    [self setScrollView:nil];
    
    __weak JTSImageViewController *weakSelf = self;
    
    // Have to dispatch after or else the image view changes above won't be
    // committed prior to the animations below. A single dispatch_async(dispatch_get_main_queue()
    // wouldn't work under certain scrolling conditions, so it has to be an ugly
    // two runloops ahead.
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            
            CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
            if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
                duration *= 4;
            }
            
            [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
                
                weakSelf.snapshotView.transform = weakSelf.currentSnapshotRotationTransform;
                [weakSelf removeMotionEffectsFromSnapshotView];
                [weakSelf.blackBackdrop setAlpha:0];
                
                if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
                    [weakSelf.blurredSnapshotView setAlpha:0];
                }
                
                BOOL mustRotateDuringTransition = ([UIApplication sharedApplication].statusBarOrientation != _startingInfo.startingInterfaceOrientation);
                if (mustRotateDuringTransition) {
                    CGRect newEndingRect;
                    CGPoint centerInRect;
                    if (_startingInfo.presentingViewControllerPresentedFromItsUnsupportedOrientation) {
                        CGRect rectToConvert = _startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation;
                        CGRect rectForCentering = [weakSelf.snapshotView convertRect:rectToConvert toView:weakSelf.view];
                        centerInRect = CGPointMake(rectForCentering.origin.x+rectForCentering.size.width/2.0f,
                                                   rectForCentering.origin.y+rectForCentering.size.height/2.0f);
                        newEndingRect = _startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation;
                    } else {
                        newEndingRect = _startingInfo.startingReferenceFrameForThumbnail;
                        CGRect rectForCentering = [weakSelf.snapshotView convertRect:_startingInfo.startingReferenceFrameForThumbnail toView:weakSelf.view];
                        centerInRect = CGPointMake(rectForCentering.origin.x+rectForCentering.size.width/2.0f,
                                                   rectForCentering.origin.y+rectForCentering.size.height/2.0f);
                    }
                    [weakSelf.imageView setFrame:newEndingRect];
                    weakSelf.imageView.transform = weakSelf.currentSnapshotRotationTransform;
                    [weakSelf.imageView setCenter:centerInRect];
                } else {
                    if (_startingInfo.presentingViewControllerPresentedFromItsUnsupportedOrientation) {
                        [weakSelf.imageView setFrame:_startingInfo.startingReferenceFrameForThumbnailInPresentingViewControllersOriginalOrientation];
                    } else {
                        [weakSelf.imageView setFrame:_startingInfo.startingReferenceFrameForThumbnail];
                    }
                    
                    // Rotation not needed, so fade the status bar back in. Looks nicer.
                    if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
                        [weakSelf setNeedsStatusBarAppearanceUpdate];
                    } else {
                        [[UIApplication sharedApplication] setStatusBarHidden:_startingInfo.statusBarHiddenPriorToPresentation
                                                                withAnimation:UIStatusBarAnimationFade];
                    }
                }
            } completion:^(BOOL finished) {
                
                // Needed if dismissing from a different orientation then the one we started with
                if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance == NO) {
                    [[UIApplication sharedApplication] setStatusBarHidden:_startingInfo.statusBarHiddenPriorToPresentation
                                                            withAnimation:UIStatusBarAnimationNone];
                }
                
                [weakSelf.presentingViewController dismissViewControllerAnimated:NO completion:^{
                    [weakSelf.dismissalDelegate imageViewerDidDismiss:weakSelf];
                }];
            }];
        });
    });
}

- (void)dismissByCleaningUpAfterImageWasFlickedOffscreen {
    
    [self.view setUserInteractionEnabled:NO];
    _flags.isAnimatingAPresentationOrDismissal = YES ;
    _flags.isDismissing = YES;
    
    __weak JTSImageViewController *weakSelf = self;
    
    CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
    if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
        duration *= 4;
    }
    
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        weakSelf.snapshotView.transform = weakSelf.currentSnapshotRotationTransform;
        [weakSelf removeMotionEffectsFromSnapshotView];
        [weakSelf.blackBackdrop setAlpha:0];
        if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
            [weakSelf.blurredSnapshotView setAlpha:0];
        }
        [weakSelf.scrollView setAlpha:0];
        if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
            [weakSelf setNeedsStatusBarAppearanceUpdate];
        } else {
            [[UIApplication sharedApplication] setStatusBarHidden:_startingInfo.statusBarHiddenPriorToPresentation
                                                    withAnimation:UIStatusBarAnimationFade];
        }
    } completion:^(BOOL finished) {
        [weakSelf.presentingViewController dismissViewControllerAnimated:NO completion:^{
            [weakSelf.dismissalDelegate imageViewerDidDismiss:weakSelf];
        }];
    }];
}

- (void)dismissByExpandingImageToOffscreenPosition {
    
    [self.view setUserInteractionEnabled:NO];
    _flags.isAnimatingAPresentationOrDismissal = YES;
    _flags.isDismissing = YES;
    
    __weak JTSImageViewController *weakSelf = self;
    
    CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
    if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
        duration *= 4;
    }
    
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        weakSelf.snapshotView.transform = weakSelf.currentSnapshotRotationTransform;
        [weakSelf removeMotionEffectsFromSnapshotView];
        [weakSelf.blackBackdrop setAlpha:0];
        if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
            [weakSelf.blurredSnapshotView setAlpha:0];
        }
        [weakSelf.scrollView setAlpha:0];
        CGFloat scaling = JTSImageViewController_MaxScalingForExpandingOffscreenStyleTransition;
        [weakSelf.scrollView setTransform:CGAffineTransformMakeScale(scaling, scaling)];
        if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
            [weakSelf setNeedsStatusBarAppearanceUpdate];
        } else {
            [[UIApplication sharedApplication] setStatusBarHidden:_startingInfo.statusBarHiddenPriorToPresentation
                                                    withAnimation:UIStatusBarAnimationFade];
        }
    } completion:^(BOOL finished) {
        [weakSelf.presentingViewController dismissViewControllerAnimated:NO completion:^{
            [weakSelf.dismissalDelegate imageViewerDidDismiss:weakSelf];
        }];
    }];
}

- (void)dismissByExpandingAltTextToOffscreenPosition {
    
    [self.view setUserInteractionEnabled:NO];
    _flags.isAnimatingAPresentationOrDismissal = YES;
    _flags.isDismissing = YES;
    
    __weak JTSImageViewController *weakSelf = self;
    
    CGFloat duration = JTSImageViewController_TransitionAnimationDuration;
    if (USE_DEBUG_SLOW_ANIMATIONS == 1) {
        duration *= 4;
    }
    
    // Replace the text view with a snapshot of itself,
    // to prevent the text from reflowing during the dismissal animation.
    UIView *textViewSnapshot = [self.textView snapshotViewAfterScreenUpdates:YES];
    [textViewSnapshot setFrame:self.textView.frame];
    [self.textView.superview insertSubview:textViewSnapshot aboveSubview:self.textView];
    [self.textView removeFromSuperview];
    [self.textView setDelegate:nil];
    [self setTextView:nil];
    
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        weakSelf.snapshotView.transform = weakSelf.currentSnapshotRotationTransform;
        [weakSelf removeMotionEffectsFromSnapshotView];
        [weakSelf.blackBackdrop setAlpha:0];
        [textViewSnapshot setAlpha:0];
        if (weakSelf.backgroundStyle == JTSImageViewControllerBackgroundStyle_ScaledDimmedBlurred) {
            [weakSelf.blurredSnapshotView setAlpha:0];
        }
        CGFloat targetScale = JTSImageViewController_MaxScalingForExpandingOffscreenStyleTransition;
        [textViewSnapshot setTransform:CGAffineTransformMakeScale(targetScale, targetScale)];
        if ([UIApplication sharedApplication].jts_usesViewControllerBasedStatusBarAppearance) {
            [weakSelf setNeedsStatusBarAppearanceUpdate];
        } else {
            [[UIApplication sharedApplication] setStatusBarHidden:_startingInfo.statusBarHiddenPriorToPresentation
                                                    withAnimation:UIStatusBarAnimationFade];
        }
    } completion:^(BOOL finished) {
        [weakSelf.presentingViewController dismissViewControllerAnimated:NO completion:^{
            [weakSelf.dismissalDelegate imageViewerDidDismiss:weakSelf];
        }];
    }];
}

#pragma mark - Snapshots

- (UIView *)snapshotFromParentmostViewController:(UIViewController *)viewController {
    
    UIViewController *presentingViewController = viewController.view.window.rootViewController;
    while (presentingViewController.presentedViewController) presentingViewController = presentingViewController.presentedViewController;
    UIView *snapshot = [presentingViewController.view snapshotViewAfterScreenUpdates:YES];
    [snapshot setClipsToBounds:NO];
    return snapshot;
}

- (UIView *)blurredSnapshotFromParentmostViewController:(UIViewController *)viewController {
    
    UIViewController *presentingViewController = viewController.view.window.rootViewController;
    while (presentingViewController.presentedViewController) presentingViewController = presentingViewController.presentedViewController;
    
    // We'll draw the presentingViewController's view into a context
    // that is scaled down by a factor of 4, which will dramatically improve
    // the performance of JTS_applyBlurWithRadius:tintColor:saturationDeltaFactor:maskImage:
    
    CGFloat outerBleed = 20.0f;
    CGFloat performanceDownScalingFactor = 0.25f;
    CGFloat scaledOuterBleed = outerBleed * performanceDownScalingFactor;
    CGRect contextBounds = CGRectInset(presentingViewController.view.bounds, -outerBleed, -outerBleed);
    CGRect scaledBounds = contextBounds;
    scaledBounds.size.width *= performanceDownScalingFactor;
    scaledBounds.size.height *= performanceDownScalingFactor;
    CGRect scaledDrawingArea = presentingViewController.view.bounds;
    scaledDrawingArea.size.width *= performanceDownScalingFactor;
    scaledDrawingArea.size.height *= performanceDownScalingFactor;
    
    UIGraphicsBeginImageContextWithOptions(scaledBounds.size, YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextConcatCTM(context, CGAffineTransformMakeTranslation(scaledOuterBleed, scaledOuterBleed));
    [presentingViewController.view drawViewHierarchyInRect:scaledDrawingArea afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    CGFloat blurRadius = self.backgroundBlurRadius * performanceDownScalingFactor;
    UIImage *blurredImage = [image JTS_applyBlurWithRadius:blurRadius tintColor:nil saturationDeltaFactor:1.0f maskImage:nil];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:contextBounds];
    [imageView setImage:blurredImage];
    [imageView setAutoresizingMask:UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth];
    [imageView setBackgroundColor:[UIColor blackColor]];
    
    return imageView;
}

#pragma mark - Motion Effects

- (void)addMotionEffectsToSnapshotView {
    UIInterpolatingMotionEffect *verticalEffect;
    verticalEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    verticalEffect.minimumRelativeValue = @(12);
    verticalEffect.maximumRelativeValue = @(-12);
    
    UIInterpolatingMotionEffect *horizontalEffect;
    horizontalEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    horizontalEffect.minimumRelativeValue = @(12);
    horizontalEffect.maximumRelativeValue = @(-12);
    
    UIMotionEffectGroup *effectGroup = [[UIMotionEffectGroup alloc] init];
    [effectGroup setMotionEffects:@[horizontalEffect, verticalEffect]];
    [self.snapshotView addMotionEffect:effectGroup];
}

- (void)removeMotionEffectsFromSnapshotView {
    for (UIMotionEffect *effect in self.snapshotView.motionEffects) {
        [self.snapshotView removeMotionEffect:effect];
    }
}

#pragma mark - Interface Updates

- (void)updateInterfaceWithImage:(UIImage *)image {
    
    if (image) {
        [self setImage:image];
        [self.imageView setImage:image];
        [self.progressContainer setAlpha:0];
        
        self.imageView.backgroundColor = [self backgroundColorForImageView];
        
        // Don't update the layouts during a drag.
        if (_flags.isDraggingImage == NO) {
            [self updateLayoutsForCurrentOrientation];
        }
    }
}

- (void)updateLayoutsForCurrentOrientation {
    
    if (self.mode == JTSImageViewControllerMode_Image) {
        [self updateScrollViewAndImageViewForCurrentMetrics];
        self.progressContainer.center = CGPointMake(self.view.bounds.size.width/2.0f, self.view.bounds.size.height/2.0f);
    }
    else if (self.mode == JTSImageViewControllerMode_AltText) {
        if (_flags.isTransitioningFromInitialModalToInteractiveState == NO) {
            [self verticallyCenterTextInTextView];
        }
    }
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    if (_startingInfo.startingInterfaceOrientation == UIInterfaceOrientationPortrait) {
        switch ([UIApplication sharedApplication].statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                transform = CGAffineTransformMakeRotation(M_PI/2.0f);
                break;
            case UIInterfaceOrientationLandscapeRight:
                transform = CGAffineTransformMakeRotation(-M_PI/2.0f);
                break;
            case UIInterfaceOrientationPortrait:
                transform = CGAffineTransformIdentity;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                transform = CGAffineTransformMakeRotation(M_PI);
                break;
            default:
                break;
        }
    }
    else if (_startingInfo.startingInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        switch ([UIApplication sharedApplication].statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                transform = CGAffineTransformMakeRotation(-M_PI/2.0f);
                break;
            case UIInterfaceOrientationLandscapeRight:
                transform = CGAffineTransformMakeRotation(M_PI/2.0f);
                break;
            case UIInterfaceOrientationPortrait:
                transform = CGAffineTransformMakeRotation(M_PI);
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                transform = CGAffineTransformIdentity;
                break;
            default:
                break;
        }
    }
    else if (_startingInfo.startingInterfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
        switch ([UIApplication sharedApplication].statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                transform = CGAffineTransformIdentity;
                break;
            case UIInterfaceOrientationLandscapeRight:
                transform = CGAffineTransformMakeRotation(M_PI);
                break;
            case UIInterfaceOrientationPortrait:
                transform = CGAffineTransformMakeRotation(-M_PI/2.0f);
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                transform = CGAffineTransformMakeRotation(M_PI/2.0f);
                break;
            default:
                break;
        }
    }
    else if (_startingInfo.startingInterfaceOrientation == UIInterfaceOrientationLandscapeRight) {
        switch ([UIApplication sharedApplication].statusBarOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                transform = CGAffineTransformMakeRotation(M_PI);
                break;
            case UIInterfaceOrientationLandscapeRight:
                transform = CGAffineTransformIdentity;
                break;
            case UIInterfaceOrientationPortrait:
                transform = CGAffineTransformMakeRotation(M_PI/2.0f);
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                transform = CGAffineTransformMakeRotation(-M_PI/2.0f);
                break;
            default:
                break;
        }
    }
    
    self.snapshotView.center = CGPointMake(self.view.bounds.size.width/2.0f, self.view.bounds.size.height/2.0f);
    
    if (_flags.rotationTransformIsDirty) {
        _flags.rotationTransformIsDirty = NO;
        self.currentSnapshotRotationTransform = transform;
        if (_flags.isPresented) {
            if (self.mode == JTSImageViewControllerMode_Image) {
                self.scrollView.frame = self.view.bounds;
            }
            CGFloat scaling = JTSImageViewController_MinimumBackgroundScaling;
            self.snapshotView.transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(scaling, scaling));
        } else {
            self.snapshotView.transform = transform;
        }
    }
}

- (void)updateScrollViewAndImageViewForCurrentMetrics {
    
    if (_flags.isAnimatingAPresentationOrDismissal == NO) {
        _flags.isManuallyResizingTheScrollViewFrame = YES;
        self.scrollView.frame = self.view.bounds;
        _flags.isManuallyResizingTheScrollViewFrame = NO;
    }
    
    BOOL usingOriginalPositionTransition = (self.transition == JTSImageViewControllerTransition_FromOriginalPosition);
    
    BOOL suppressAdjustments = (usingOriginalPositionTransition && _flags.isAnimatingAPresentationOrDismissal);
    
    if (suppressAdjustments == NO) {
        if (self.image) {
            [self.imageView setFrame:[self resizedFrameForAutorotatingImageView:self.image.size]];
        } else {
            [self.imageView setFrame:[self resizedFrameForAutorotatingImageView:self.imageInfo.referenceRect.size]];
        }
        self.scrollView.contentSize = self.imageView.frame.size;
        self.scrollView.contentInset = [self contentInsetForScrollView:self.scrollView.zoomScale];
    }
}

- (void)verticallyCenterTextInTextView {
    CGRect boundingRect = [self.textView.layoutManager usedRectForTextContainer:self.textView.textContainer];
    UIEdgeInsets insets = self.textView.contentInset;
    if (self.view.bounds.size.height > boundingRect.size.height) {
        insets.top = roundf(self.view.bounds.size.height-boundingRect.size.height)/2.0f;
    } else {
        insets.top = 0;
    }
    [self.textView setContentInset:insets];
    [self.textView setContentOffset:CGPointMake(0, 0 - insets.top)];
}

- (UIEdgeInsets)contentInsetForScrollView:(CGFloat)targetZoomScale {
    UIEdgeInsets inset = UIEdgeInsetsZero;
    CGFloat boundsHeight = self.scrollView.bounds.size.height;
    CGFloat boundsWidth = self.scrollView.bounds.size.width;
    CGFloat contentHeight = (self.image.size.height > 0) ? self.image.size.height : boundsHeight;
    CGFloat contentWidth = (self.image.size.width > 0) ? self.image.size.width : boundsWidth;
    CGFloat minContentHeight;
    CGFloat minContentWidth;
    if (contentHeight > contentWidth) {
        if (boundsHeight/boundsWidth < contentHeight/contentWidth) {
            minContentHeight = boundsHeight;
            minContentWidth = contentWidth * (minContentHeight / contentHeight);
        } else {
            minContentWidth = boundsWidth;
            minContentHeight = contentHeight * (minContentWidth / contentWidth);
        }
    } else {
        if (boundsWidth/boundsHeight < contentWidth/contentHeight) {
            minContentWidth = boundsWidth;
            minContentHeight = contentHeight * (minContentWidth / contentWidth);
        } else {
            minContentHeight = boundsHeight;
            minContentWidth = contentWidth * (minContentHeight / contentHeight);
        }
    }
    CGFloat myHeight = self.view.bounds.size.height;
    CGFloat myWidth = self.view.bounds.size.width;
    minContentWidth *= targetZoomScale;
    minContentHeight *= targetZoomScale;
    if (minContentHeight > myHeight && minContentWidth > myWidth) {
        inset = UIEdgeInsetsZero;
    } else {
        CGFloat verticalDiff = boundsHeight - minContentHeight;
        CGFloat horizontalDiff = boundsWidth - minContentWidth;
        verticalDiff = (verticalDiff > 0) ? verticalDiff : 0;
        horizontalDiff = (horizontalDiff > 0) ? horizontalDiff : 0;
        inset.top = verticalDiff/2.0f;
        inset.bottom = verticalDiff/2.0f;
        inset.left = horizontalDiff/2.0f;
        inset.right = horizontalDiff/2.0f;
    }
    return inset;
}

- (CGRect)resizedFrameForAutorotatingImageView:(CGSize)imageSize {
    CGRect frame = self.view.bounds;
    CGFloat screenWidth = frame.size.width * self.scrollView.zoomScale;
    CGFloat screenHeight = frame.size.height * self.scrollView.zoomScale;
    CGFloat targetWidth = screenWidth;
    CGFloat targetHeight = screenHeight;
    CGFloat nativeHeight = screenHeight;
    CGFloat nativeWidth = screenWidth;
    if (imageSize.width > 0 && imageSize.height > 0) {
        nativeHeight = (imageSize.height > 0) ? imageSize.height : screenHeight;
        nativeWidth = (imageSize.width > 0) ? imageSize.width : screenWidth;
    }
    if (nativeHeight > nativeWidth) {
        if (screenHeight/screenWidth < nativeHeight/nativeWidth) {
            targetWidth = screenHeight / (nativeHeight / nativeWidth);
        } else {
            targetHeight = screenWidth / (nativeWidth / nativeHeight);
        }
    } else {
        if (screenWidth/screenHeight < nativeWidth/nativeHeight) {
            targetHeight = screenWidth / (nativeWidth / nativeHeight);
        } else {
            targetWidth = screenHeight / (nativeHeight / nativeWidth);
        }
    }
    frame.size = CGSizeMake(targetWidth, targetHeight);
    frame.origin = CGPointMake(0, 0);
    return frame;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    
    if (_flags.imageIsFlickingAwayForDismissal) {
        return;
    }
    
    [scrollView setContentInset:[self contentInsetForScrollView:scrollView.zoomScale]];
    
    if (self.scrollView.scrollEnabled == NO) {
        self.scrollView.scrollEnabled = YES;
    }
    
    if (_flags.isAnimatingAPresentationOrDismissal == NO && _flags.isManuallyResizingTheScrollViewFrame == NO) {
        [self updateDimmingViewForCurrentZoomScale:YES];
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    
    if (_flags.imageIsFlickingAwayForDismissal) {
        return;
    }
    
    self.scrollView.scrollEnabled = (scale > 1);
    self.scrollView.contentInset = [self contentInsetForScrollView:scale];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    
    if (_flags.imageIsFlickingAwayForDismissal) {
        return;
    }
    
    CGPoint velocity = [scrollView.panGestureRecognizer velocityInView:scrollView.panGestureRecognizer.view];
    if (scrollView.zoomScale == 1 && (fabsf(velocity.x) > 1600 || fabsf(velocity.y) > 1600 ) ) {
        [self dismiss:YES];
    }
}

#pragma mark - Update Dimming View for Zoom Scale

- (void)updateDimmingViewForCurrentZoomScale:(BOOL)animated {
    CGFloat targetAlpha = (self.scrollView.zoomScale > 1) ? 1.0f : self.alphaForBackgroundDimmingOverlay;
    CGFloat duration = (animated) ? 0.35 : 0;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self.blackBackdrop setAlpha:targetAlpha];
    } completion:nil];
}

#pragma mark - Gesture Recognizer Actions

- (void)imageDoubleTapped:(UITapGestureRecognizer *)sender {
    
    if (_flags.scrollViewIsAnimatingAZoom) {
        return;
    }
    
    CGPoint rawLocation = [sender locationInView:sender.view];
    CGPoint point = [self.scrollView convertPoint:rawLocation fromView:sender.view];
    CGRect targetZoomRect;
    UIEdgeInsets targetInsets;
    if (self.scrollView.zoomScale == 1.0f) {
        self.scrollView.accessibilityHint = self.accessibilityHintZoomedIn;
        CGFloat zoomWidth = self.view.bounds.size.width / JTSImageViewController_TargetZoomForDoubleTap;
        CGFloat zoomHeight = self.view.bounds.size.height / JTSImageViewController_TargetZoomForDoubleTap;
        targetZoomRect = CGRectMake(point.x - (zoomWidth/2.0f), point.y - (zoomHeight/2.0f), zoomWidth, zoomHeight);
        targetInsets = [self contentInsetForScrollView:JTSImageViewController_TargetZoomForDoubleTap];
    } else {
        self.scrollView.accessibilityHint = self.accessibilityHintZoomedOut;
        CGFloat zoomWidth = self.view.bounds.size.width * self.scrollView.zoomScale;
        CGFloat zoomHeight = self.view.bounds.size.height * self.scrollView.zoomScale;
        targetZoomRect = CGRectMake(point.x - (zoomWidth/2.0f), point.y - (zoomHeight/2.0f), zoomWidth, zoomHeight);
        targetInsets = [self contentInsetForScrollView:1.0f];
    }
    [self.view setUserInteractionEnabled:NO];
    _flags.scrollViewIsAnimatingAZoom = YES;
    [self.scrollView setContentInset:targetInsets];
    [self.scrollView zoomToRect:targetZoomRect animated:YES];
    __weak JTSImageViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.35 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weakSelf.view setUserInteractionEnabled:YES];
        _flags.scrollViewIsAnimatingAZoom = NO;
    });
}

- (void)imageSingleTapped:(id)sender {
    if (_flags.scrollViewIsAnimatingAZoom) {
        return;
    }
    [self dismiss:YES];
}

- (void)imageLongPressed:(UILongPressGestureRecognizer *)sender {
    
    if (_flags.scrollViewIsAnimatingAZoom) {
        return;
    }
    
    if (self.image && sender.state == UIGestureRecognizerStateBegan) {
        if ([self.interactionsDelegate respondsToSelector:@selector(imageViewerDidLongPress:atRect:)]) {
            CGPoint location = [sender locationInView:self.view];
            [self.interactionsDelegate imageViewerDidLongPress:self atRect:CGRectMake(location.x, location.y, 0.0f, 0.0f)];
        }
        
        BOOL allowCopy = NO;
        
        if ([self.interactionsDelegate respondsToSelector:@selector(imageViewerAllowCopyToPasteboard:)]) {
            allowCopy = [self.interactionsDelegate imageViewerAllowCopyToPasteboard:self];
        }
        
        if (allowCopy) {
            CGPoint location = [sender locationInView:self.imageView];
            UIMenuController *menuController = [UIMenuController sharedMenuController];
            
            [menuController setTargetRect:CGRectMake(location.x, location.y, 0.0f, 0.0f) inView:self.imageView];
            [menuController setMenuVisible:YES animated:YES];
        }
    }
}

- (void)dismissingPanGestureRecognizerPanned:(UIPanGestureRecognizer *)panner {
    
    if (_flags.scrollViewIsAnimatingAZoom || _flags.isAnimatingAPresentationOrDismissal) {
        return;
    }
    
    CGPoint translation = [panner translationInView:panner.view];
    CGPoint locationInView = [panner locationInView:panner.view];
    CGPoint velocity = [panner velocityInView:panner.view];
    CGFloat vectorDistance = sqrtf(powf(velocity.x, 2)+powf(velocity.y, 2));
    
    if (panner.state == UIGestureRecognizerStateBegan) {
        _flags.isDraggingImage = CGRectContainsPoint(self.imageView.frame, locationInView);
        if (_flags.isDraggingImage) {
            [self startImageDragging:locationInView translationOffset:UIOffsetZero];
        }
    }
    else if (panner.state == UIGestureRecognizerStateChanged) {
        if (_flags.isDraggingImage) {
            CGPoint newAnchor = self.imageDragStartingPoint;
            newAnchor.x += translation.x + self.imageDragOffsetFromActualTranslation.horizontal;
            newAnchor.y += translation.y + self.imageDragOffsetFromActualTranslation.vertical;
            [self.attachmentBehavior setAnchorPoint:newAnchor];
        } else {
            _flags.isDraggingImage = CGRectContainsPoint(self.imageView.frame, locationInView);
            if (_flags.isDraggingImage) {
                UIOffset translationOffset = UIOffsetMake(-1*translation.x, -1*translation.y);
                [self startImageDragging:locationInView translationOffset:translationOffset];
            }
        }
    }
    else {
        if (vectorDistance > JTSImageViewController_MinimumFlickDismissalVelocity) {
            if (_flags.isDraggingImage) {
                [self dismissImageWithFlick:velocity];
            } else {
                [self dismiss:YES];
            }
        }
        else {
            [self cancelCurrentImageDrag:YES];
        }
    }
}

- (void)textViewSingleTapped:(id)sender {
    [self dismiss:YES];
}

#pragma mark - Dynamic Image Dragging

- (void)startImageDragging:(CGPoint)panGestureLocationInView translationOffset:(UIOffset)translationOffset {
    self.imageDragStartingPoint = panGestureLocationInView;
    self.imageDragOffsetFromActualTranslation = translationOffset;
    CGPoint anchor = self.imageDragStartingPoint;
    CGPoint imageCenter = self.imageView.center;
    UIOffset offset = UIOffsetMake(panGestureLocationInView.x-imageCenter.x, panGestureLocationInView.y-imageCenter.y);
    self.imageDragOffsetFromImageCenter = offset;
    self.attachmentBehavior = [[UIAttachmentBehavior alloc] initWithItem:self.imageView offsetFromCenter:offset attachedToAnchor:anchor];
    [self.animator addBehavior:self.attachmentBehavior];
    UIDynamicItemBehavior *modifier = [[UIDynamicItemBehavior alloc] initWithItems:@[self.imageView]];
    [modifier setAngularResistance:[self appropriateAngularResistanceForView:self.imageView]];
    [modifier setDensity:[self appropriateDensityForView:self.imageView]];
    [self.animator addBehavior:modifier];
}

- (void)cancelCurrentImageDrag:(BOOL)animated {
    [self.animator removeAllBehaviors];
    [self setAttachmentBehavior:nil];
    _flags.isDraggingImage = NO;
    if (animated == NO) {
        self.imageView.transform = CGAffineTransformIdentity;
        self.imageView.center = CGPointMake(self.scrollView.contentSize.width/2.0f, self.scrollView.contentSize.height/2.0f);
    } else {
        [UIView
         animateWithDuration:0.7
         delay:0
         usingSpringWithDamping:0.7
         initialSpringVelocity:0
         options:UIViewAnimationOptionAllowUserInteraction |
         UIViewAnimationOptionBeginFromCurrentState
         animations:^{
             if (_flags.isDraggingImage == NO) {
                 self.imageView.transform = CGAffineTransformIdentity;
                 if (self.scrollView.dragging == NO && self.scrollView.decelerating == NO) {
                     self.imageView.center = CGPointMake(self.scrollView.contentSize.width/2.0f, self.scrollView.contentSize.height/2.0f);
                     [self updateScrollViewAndImageViewForCurrentMetrics];
                 }
             }
         } completion:nil];
    }
}

- (void)dismissImageWithFlick:(CGPoint)velocity {
    _flags.imageIsFlickingAwayForDismissal = YES;
    __weak JTSImageViewController *weakSelf = self;
    UIPushBehavior *push = [[UIPushBehavior alloc] initWithItems:@[self.imageView] mode:UIPushBehaviorModeInstantaneous];
    [push setPushDirection:CGVectorMake(velocity.x*0.1, velocity.y*0.1)];
    [push setTargetOffsetFromCenter:self.imageDragOffsetFromImageCenter forItem:self.imageView];
    [push setAction:^{
        if ([weakSelf imageViewIsOffscreen]) {
            [weakSelf.animator removeAllBehaviors];
            [weakSelf setAttachmentBehavior:nil];
            [weakSelf.imageView removeFromSuperview];
            [weakSelf dismiss:YES];
        }
    }];
    [self.animator removeBehavior:self.attachmentBehavior];
    [self.animator addBehavior:push];
}

- (CGFloat)appropriateAngularResistanceForView:(UIView *)view {
    CGFloat height = view.bounds.size.height;
    CGFloat width = view.bounds.size.width;
    CGFloat actualArea = height * width;
    CGFloat referenceArea = self.view.bounds.size.width * self.view.bounds.size.height;
    CGFloat factor = referenceArea / actualArea;
    CGFloat defaultResistance = 4.0f; // Feels good with a 1x1 on 3.5 inch displays. We'll adjust this to match the current display.
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat resistance = defaultResistance * ((320.0 * 480.0) / (screenWidth * screenHeight));
    return resistance * factor;
}

- (CGFloat)appropriateDensityForView:(UIView *)view {
    CGFloat height = view.bounds.size.height;
    CGFloat width = view.bounds.size.width;
    CGFloat actualArea = height * width;
    CGFloat referenceArea = self.view.bounds.size.width * self.view.bounds.size.height;
    CGFloat factor = referenceArea / actualArea;
    CGFloat defaultDensity = 0.5f; // Feels good on 3.5 inch displays. We'll adjust this to match the current display.
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat appropriateDensity = defaultDensity * ((320.0 * 480.0) / (screenWidth * screenHeight));
    return appropriateDensity * factor;
}

- (BOOL)imageViewIsOffscreen {
    CGRect visibleRect = [self.scrollView convertRect:self.view.bounds fromView:self.view];
    return ([self.animator itemsInRect:visibleRect].count == 0);
}

- (CGPoint)targetDismissalPoint:(CGPoint)startingCenter velocity:(CGPoint)velocity {
    return CGPointMake(startingCenter.x + velocity.x/3.0 , startingCenter.y + velocity.y/3.0);
}

#pragma mark - Gesture Recognizer Delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    
    BOOL shouldReceiveTouch = YES;
    
    if ([self.interactionsDelegate respondsToSelector:@selector(imageViewerShouldTemporarilyIgnoreTouches:)]) {
        shouldReceiveTouch = ![self.interactionsDelegate imageViewerShouldTemporarilyIgnoreTouches:self];
    }
    
    if (shouldReceiveTouch && gestureRecognizer == self.panRecognizer) {
        shouldReceiveTouch = (self.scrollView.zoomScale == 1 && _flags.scrollViewIsAnimatingAZoom == NO);
    }
    
    return shouldReceiveTouch;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return (gestureRecognizer == self.singleTapperText);
}

#pragma mark - Progress Bar

- (void)startProgressTimer {
    NSTimer *timer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:0.05 target:self selector:@selector(progressTimerFired:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [self setDownloadProgressTimer:timer];
}

- (void)cancelProgressTimer {
    [self.downloadProgressTimer invalidate];
    [self setDownloadProgressTimer:nil];
}

- (void)progressTimerFired:(NSTimer *)timer {
    CGFloat progress = 0;
    CGFloat bytesExpected = self.imageDownloadDataTask.countOfBytesExpectedToReceive;
    if (bytesExpected > 0 && _flags.imageIsBeingReadFromDisk == NO) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear animations:^{
            self.spinner.alpha = 0;
            self.progressView.alpha = 1;
        } completion:nil];
        progress = self.imageDownloadDataTask.countOfBytesReceived / bytesExpected;
    }
    [self.progressView setProgress:progress];
}

#pragma mark - UIResponder

- (BOOL)canBecomeFirstResponder {
    
    if (self.image) {
        return YES;
    }
    return NO;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    
    if (self.image && action == @selector(copy:)) {
        return YES;
    }
    return NO;
}

- (void)copy:(id)sender {
    [[UIPasteboard generalPasteboard] setImage:self.image];
}

#pragma mark - Accessibility

- (NSString *)accessibilityHintZoomedOut {
    
    NSString *hint = nil;
    
    if ([self.accessibilityDelegate respondsToSelector:@selector(accessibilityHintZoomedOutForImageViewer:)]) {
        hint = [self.accessibilityDelegate accessibilityHintZoomedOutForImageViewer:self];
    } else {
        hint = [self defaultAccessibilityHintForScrollView:NO];
    }
    
    return hint;
}

- (NSString *)accessibilityHintZoomedIn {
    
    NSString *hint = nil;
    
    if ([self.accessibilityDelegate respondsToSelector:@selector(accessibilityHintZoomedInForImageViewer:)]) {
        hint = [self.accessibilityDelegate accessibilityHintZoomedInForImageViewer:self];
    } else {
        hint = [self defaultAccessibilityHintForScrollView:YES];
    }
    
    return hint;
}

- (NSString *)defaultAccessibilityLabelForScrollView {
    
    return @"Full-Screen Image Viewer";
}

- (NSString *)defaultAccessibilityHintForScrollView:(BOOL)zoomedIn {
    
    NSString *hint = nil;
    
    if (zoomedIn) {
        hint = @"\
        Image is zoomed in. \
        Pan around the image using three fingers. \
        Double tap to dismiss this screen. \
        Double tap and hold for more options. \
        Triple tap the image to zoom out.";
    } else {
        hint = @"\
        Image is zoomed out. \
        Double tap to dismiss this screen. \
        Double tap and hold for more options. \
        Triple tap the image to zoom in.";
    }
    
    return hint;
}

@end



