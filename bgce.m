#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *kWXKeyBeauty = @"wx_beauty";
static NSString *kWXKeyMirror  = @"wx_mirror";
static NSString *kWXKeyMuteRingtone = @"wx_mute_ring";
static NSString *kWXKeyFavLock = @"wx_fav_lock";

static UIViewController *gMoreVC = nil;

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

static UILabel *WXFindLabel(UIView *v, NSString *text) {
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *lb = (UILabel *)v;
        if (lb.text && [lb.text isEqualToString:text]) return lb;
    }
    for (UIView *sv in v.subviews) {
        UILabel *lb = WXFindLabel(sv, text);
        if (lb) return lb;
    }
    return nil;
}

static void WXOpenFavWithPassword(void) {
    UIViewController *top = WXTopVC();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收藏上锁" message:@"请输入密码" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"密码";
        tf.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UITextField *tf = alert.textFields.firstObject;
        if ([tf.text isEqualToString:@"1234"]) {
            // 调试: 显示gMoreVC的信息
            NSMutableString *msg = [NSMutableString string];
            [msg appendFormat:@"gMoreVC: %@\n", gMoreVC ? @"有" : @"无"];
            if (gMoreVC) {
                [msg appendFormat:@"类: %@\n", NSStringFromClass([gMoreVC class])];
                [msg appendFormat:@"响应onOpen: %@\n", [gMoreVC respondsToSelector:@selector(onOpenMyFavoritesListController)] ? @"是" : @"否"];
                [msg appendFormat:@"响应showFav: %@\n", [gMoreVC respondsToSelector:@selector(showFavoriteView)] ? @"是" : @"否"];
            }
            UIViewController *vc = WXTopVC();
            UIAlertController *a2 = [UIAlertController alertControllerWithTitle:@"调试" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [a2 addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [vc presentViewController:a2 animated:YES completion:nil];
        }
    }]];
    [top presentViewController:alert animated:YES completion:nil];
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
    [ac addAction:[UIAlertAction actionWithTitle:@"打开收藏(调试)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXOpenFavWithPassword(); }]];
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

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
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

        Class moreCls = NSClassFromString(@"MoreViewController");
        if (moreCls) {
            Method m = class_getInstanceMethod(moreCls, @selector(viewDidAppear:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
                    ((void(*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
                    gMoreVC = (UIViewController *)self;
                    if (!WXGet(kWXKeyFavLock)) return;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        @try {
                            UIView *rootView = [(UIViewController *)self view];
                            UILabel *favLabel = WXFindLabel(rootView, @"收藏");
                            if (favLabel) {
                                UIView *cell = favLabel;
                                while (cell && ![cell isKindOfClass:[UITableViewCell class]]) {
                                    cell = cell.superview;
                                }
                                if (cell) cell.hidden = YES;
                            }
                        } @catch (__unused NSException *e) {}
                    });
                }));
            }
        }

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