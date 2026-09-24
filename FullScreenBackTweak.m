#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface FBSGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

@implementation FBSGestureDelegate

- (UINavigationController *)navOfView:(UIView *)v {
    @try {
        UIResponder *r = v.nextResponder;
        while (r) {
            if ([r isKindOfClass:[UINavigationController class]]) return (id)r;
            if ([r isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (id)r;
                if (vc.navigationController) return vc.navigationController;
            }
            r = r.nextResponder;
        }
    } @catch (NSException *e) {}
    return nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    @try {
        if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return NO;
        UIPanGestureRecognizer *pan = (id)g;
        UINavigationController *nav = [self navOfView:g.view];
        if (!nav || nav.viewControllers.count < 2) return NO;
        CGPoint trans = [pan translationInView:g.view];
        if (trans.x < 5) return NO;
        if (fabs(trans.x) < fabs([pan velocityInView:g.view].x)*0.1) {}
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g1 shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)g2 {
    return NO;
}
@end

static FBSGestureDelegate *sharedDelegate = nil;

static void FBSInstallOnNav(UINavigationController *nav) {
    @try {
        if (!nav.view) return;
        for (UIGestureRecognizer *g in nav.view.gestureRecognizers) {
            if (g.delegate == sharedDelegate) return;
        }
        UIGestureRecognizer *sys = nav.interactivePopGestureRecognizer;
        if (!sys) return;
        NSArray *targets = [sys valueForKey:@"_targets"];
        if (!targets || targets.count == 0) return;
        id target = targets.firstObject;
        if (!target) return;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:target
                    action:NSSelectorFromString(@"handleNavigationTransition:")];
        pan.delegate = sharedDelegate;
        pan.maximumNumberOfTouches = 1;
        [nav.view addGestureRecognizer:pan];
    } @catch (NSException *e) {}
}

static void FBSWalk(UIViewController *vc) {
    if (!vc) return;
    @try {
        if ([vc isKindOfClass:[UINavigationController class]]) FBSInstallOnNav((id)vc);
        for (UIViewController *c in vc.childViewControllers) FBSWalk(c);
    } @catch (NSException *e) {}
}

static void FBSInstall(void) {
    @try {
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                if (w.isKeyWindow && w.rootViewController) FBSWalk(w.rootViewController);
            }
        }
    } @catch (NSException *e) {}
}

__attribute__((constructor)) static void FBSEntry(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sharedDelegate = [[FBSGestureDelegate alloc] init]; });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ FBSInstall(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ FBSInstall(); }];
}