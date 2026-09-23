#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface FBSGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

@implementation FBSGestureDelegate

- (UINavigationController *)navOfView:(UIView *)v {
    UIResponder *r = v.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UINavigationController class]]) return (id)r;
        if ([r isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (id)r;
            if (vc.navigationController) return vc.navigationController;
        }
        r = r.nextResponder;
    }
    return nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return NO;
    UIPanGestureRecognizer *pan = (id)g;
    UINavigationController *nav = [self navOfView:g.view];
    if (!nav || nav.viewControllers.count < 2) return NO;
    CGPoint vel = [pan velocityInView:g.view];
    CGPoint trans = [pan translationInView:g.view];
    if (fabs(vel.x) < fabs(vel.y)) return NO;
    if (trans.x < 5) return NO;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g1 shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)g2 {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g1 shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)g2 {
    return NO;
}

@end

static FBSGestureDelegate *sharedDelegate = nil;

static void FBSInstallOnNav(UINavigationController *nav) {
    @try {
        for (UIGestureRecognizer *g in nav.view.gestureRecognizers) {
            if ([g isMemberOfClass:[UIPanGestureRecognizer class] && g.delegate == sharedDelegate]) return;
        }
        UIGestureRecognizer *sys = nav.interactivePopGestureRecognizer;
        NSArray *targets = [sys valueForKey:@"_targets"];
        if (targets.count == 0) return;
        id target = targets.firstObject;
        if (!target) return;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:target
                    action:NSSelectorFromString(@"handleNavigationTransition:")];
        pan.delegate = sharedDelegate;
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;
        [nav.view addGestureRecognizer:pan];
    } @catch (NSException *e) {}
}

static void FBSWalk(UIViewController *vc) {
    if (!vc) return;
    if ([vc isKindOfClass:[UINavigationController class]]) FBSInstallOnNav((id)vc);
    for (UIViewController *c in vc.childViewControllers) FBSWalk(c);
}

static void FBSInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                if (w.rootViewController) FBSWalk(w.rootViewController);
            }
        }
    });
}

__attribute__((constructor)) static void FBSEntry(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sharedDelegate = [[FBSGestureDelegate alloc] init]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBSInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ FBSInstall(); }];
}