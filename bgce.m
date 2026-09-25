#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *kWXKeyBeauty = @"wx_beauty";
static NSString *kWXKeyMirror  = @"wx_mirror";
static NSString *kWXKeyMuteRingtone = @"wx_mute_ring";
static NSString *kWXKeyFavLock = @"wx_fav_lock";
static NSString *kWXKeyQuickEdit = @"wx_quick_edit";

static BOOL WXGet(NSString *key) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d objectForKey:key];
    return v ? [v boolValue] : YES;
}
static void WXSet(NSString *key, BOOL val) {
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:key];
}

static UIViewController *WXTopVC(void) {
    UIWindowScene *ws = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { ws = s; break; }
    }
    if (!ws) return nil;
    UIViewController *vc = ws.windows.firstObject.rootViewController;
    while (YES) {
        if (vc.presentedViewController && ![vc.presentedViewController isBeingDismissed]) {
            vc = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *sel = [(UITabBarController *)vc selectedViewController];
            if (sel) vc = sel; else break;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *top = [(UINavigationController *)vc topViewController];
            if (top) vc = top; else break;
        } else {
            break;
        }
    }
    return vc;
}

static void WXShowSettings(void) {
    UIViewController *top = WXTopVC();
    if (!top) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"微信增强设置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL be = WXGet(kWXKeyBeauty);
    [ac addAction:[UIAlertAction actionWithTitle:be ? @"✓ 通话美颜: 开" : @"  通话美颜: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyBeauty, !be); }]];
    BOOL mi = WXGet(kWXKeyMirror);
    [ac addAction:[UIAlertAction actionWithTitle:mi ? @"✓ 通话镜像: 开" : @"  通话镜像: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyMirror, !mi); }]];
    BOOL mu = WXGet(kWXKeyMuteRingtone);
    [ac addAction:[UIAlertAction actionWithTitle:mu ? @"✓ 拨号静音: 开" : @"  拨号静音: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyMuteRingtone, !mu); }]];
    BOOL fl = WXGet(kWXKeyFavLock);
    [ac addAction:[UIAlertAction actionWithTitle:fl ? @"✓ 收藏上锁: 开" : @"  收藏上锁: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyFavLock, !fl); }]];
    BOOL qe = WXGet(kWXKeyQuickEdit);
    [ac addAction:[UIAlertAction actionWithTitle:qe ? @"✓ 快捷发送编辑: 开" : @"  快捷发送编辑: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyQuickEdit, !qe); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:ac animated:YES completion:nil];
}

@interface WXBtnTarget : NSObject
+ (instancetype)shared;
- (void)onBtn;
@end
@implementation WXBtnTarget
+ (instancetype)shared {
    static WXBtnTarget *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [WXBtnTarget new]; });
    return s;
}
- (void)onBtn { WXShowSettings(); }
@end

// 全局保存原始的tableView:didSelectRowAtIndexPath:实现
static IMP origTableViewDidSelect = NULL;

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. 通话页面
        Class voipCls = NSClassFromString(@"VoIPCallerViewController");
        if (voipCls) {
            Method m = class_getInstanceMethod(voipCls, @selector(viewDidAppear:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
                    ((void(*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
                    @try {
                        UIView *v = [(UIViewController *)self view];
                        if (WXGet(kWXKeyMuteRingtone)) {
                            AVAudioSession *session = [AVAudioSession sharedInstance];
                            [session setCategory:AVAudioSessionCategoryRecord error:nil];
                        }
                        if (WXGet(kWXKeyMirror)) {
                            for (UIView *sv in v.subviews) {
                                Class layerCls = NSClassFromString(@"AVCaptureVideoPreviewLayer");
                                if (layerCls && [sv.layer isKindOfClass:layerCls]) {
                                    [(AVCaptureVideoPreviewLayer *)sv.layer setMirrored:YES];
                                }
                            }
                        }
                        if (WXGet(kWXKeyBeauty)) {
                            for (UIView *sv in v.subviews) { if (sv.tag == 99999) return; }
                            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
                            b.frame = CGRectMake(16, 80, 44, 44);
                            b.layer.cornerRadius = 22;
                            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
                            [b setTitle:@"美" forState:UIControlStateNormal];
                            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                            b.tag = 99999;
                            [b addTarget:[WXBtnTarget shared] action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
                            [v addSubview:b];
                        }
                    } @catch (__unused NSException *e) {}
                }));
            }
        }

        // 2. hook UITableView的setDelegate:,当delegate被设置后,再hook delegate的选中方法
        Class tvCls = [UITableView class];
        Method m = class_getInstanceMethod(tvCls, @selector(setDelegate:));
        if (m) {
            __block IMP orig = method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^(UITableView *self, id delegate) {
                ((void(*)(id, SEL, id))orig)(self, @selector(setDelegate:), delegate);
                if (delegate && !origTableViewDidSelect) {
                    SEL sel = @selector(tableView:didSelectRowAtIndexPath:);
                    Method dm = class_getInstanceMethod([delegate class], sel);
                    if (dm) {
                        origTableViewDidSelect = method_getImplementation(dm);
                        method_setImplementation(dm, imp_implementationWithBlock(^(id delegateSelf, UITableView *tv, NSIndexPath *ip) {
                            if (WXGet(kWXKeyFavLock) &&
                                [NSStringFromClass([delegateSelf class]) isEqualToString:@"MoreViewController"]) {
                                UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
                                // 递归找cell里的所有label
                                NSString *text = nil;
                                NSMutableArray *labels = [NSMutableArray array];
                                void (^findLabels)(UIView *) = ^(UIView *v) {
                                    if ([v isKindOfClass:[UILabel class]]) [labels addObject:v];
                                    for (UIView *sv in v.subviews) findLabels(sv);
                                };
                                findLabels(cell);
                                for (UILabel *lb in labels) {
                                    if (lb.text && [lb.text containsString:@"收藏"]) text = lb.text;
                                }
                                if (text && [text containsString:@"收藏"]) {
                                    UIViewController *top = WXTopVC();
                                    if (top) {
                                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收藏已锁定" message:@"输入密码" preferredStyle:UIAlertControllerStyleAlert];
                                        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.secureTextEntry = YES; }];
                                        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                        [alert addAction:[UIAlertAction actionWithTitle:@"解锁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                                            if ([alert.textFields.firstObject.text isEqualToString:@"1234"]) {
                                                ((void(*)(id, SEL, id, id))origTableViewDidSelect)(delegateSelf, sel, tv, ip);
                                            }
                                        }]];
                                        [top presentViewController:alert animated:YES completion:nil];
                                        return;
                                    }
                                }
                            }
                            ((void(*)(id, SEL, id, id))origTableViewDidSelect)(delegateSelf, sel, tv, ip);
                        }));
                    }
                }
            }));
        }

        // 悬浮按钮
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                static dispatch_once_t once;
                dispatch_once(&once, ^{
                    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
                    btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 60, [UIScreen mainScreen].bounds.size.height - 220, 44, 44);
                    btn.layer.cornerRadius = 22;
                    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.85];
                    [btn setTitle:@"微" forState:UIControlStateNormal];
                    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
                    [btn addTarget:[WXBtnTarget shared] action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
                    [w addSubview:btn];
                });
            }
        }
    });
}

__attribute__((constructor)) static void WXConstructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WXInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){ WXInstall(); }];
}