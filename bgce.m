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

// 找实现了某个方法的类
static Class WXFindClassWithSelector(SEL sel) {
    unsigned int total = 0;
    Class *classes = objc_copyClassList(&total);
    Class found = nil;
    for (unsigned int i = 0; i < total; i++) {
        if (class_getInstanceMethod(classes[i], sel)) {
            found = classes[i];
            break;
        }
    }
    free(classes);
    return found;
}

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{

        // === 1. 通话美颜/镜像:hook openVideoWindowWithContact 方法 ===
        SEL videoSel = NSSelectorFromString(@"openVideoWindowWithContact:msgWrap:isCaller:from:");
        SEL audioSel = NSSelectorFromString(@"openAudioWindowWithContact:msgWrap:isCaller:from:");
        Class callCls = WXFindClassWithSelector(videoSel);
        if (!callCls) callCls = WXFindClassWithSelector(audioSel);
        if (callCls) {
            NSLog(@"[bgce] 通话类: %@", NSStringFromClass(callCls));
            // hook openVideoWindow
            Method m = class_getInstanceMethod(callCls, videoSel);
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, id contact, id msgWrap, BOOL isCaller, id from) {
                    ((void(*)(id, SEL, id, id, BOOL, id))orig)(self, videoSel, contact, msgWrap, isCaller, from);
                    if (WXGet(kWXKeyBeauty)) {
                        // 视频通话开始,可以加美颜
                        NSLog(@"[bgce] 视频通话开始");
                    }
                }));
            }
            // hook openAudioWindow
            m = class_getInstanceMethod(callCls, audioSel);
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, id contact, id msgWrap, BOOL isCaller, id from) {
                    ((void(*)(id, SEL, id, id, BOOL, id))orig)(self, audioSel, contact, msgWrap, isCaller, from);
                    if (WXGet(kWXKeyMuteRingtone)) {
                        // 语音通话开始,静音拨号音
                        NSLog(@"[bgce] 语音通话开始");
                        @try {
                            AVAudioSession *session = [AVAudioSession sharedInstance];
                            [session setCategory:AVAudioSessionCategoryRecord error:nil];
                        } @catch (__unused NSException *e) {}
                    }
                }));
            }
        }

        // === 2. 收藏上锁:hook onOpenMyFavoritesListController ===
        SEL favSel = NSSelectorFromString(@"onOpenMyFavoritesListController");
        Class favCls = WXFindClassWithSelector(favSel);
        if (favCls) {
            NSLog(@"[bgce] 收藏类: %@", NSStringFromClass(favCls));
            Method m = class_getInstanceMethod(favCls, favSel);
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self) {
                    if (WXGet(kWXKeyFavLock)) {
                        // 弹密码框或直接拦截
                        UIViewController *top = WXTopVC();
                        if (top) {
                            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收藏已锁定" message:@"请输入密码" preferredStyle:UIAlertControllerStyleAlert];
                            [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                                tf.secureTextEntry = YES;
                            }];
                            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                            [alert addAction:[UIAlertAction actionWithTitle:@"解锁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                                UITextField *tf = alert.textFields.firstObject;
                                if ([tf.text isEqualToString:@"1234"]) {
                                    ((void(*)(id, SEL))orig)(self, favSel);
                                }
                            }]];
                            [top presentViewController:alert animated:YES completion:nil];
                            return;
                        }
                    }
                    ((void(*)(id, SEL))orig)(self, favSel);
                }));
            }
        }

        // === 3. 快捷发送编辑图片:hook MMImagePickerController ===
        Class pickerCls = NSClassFromString(@"MMImagePickerController");
        if (pickerCls) {
            SEL pickSel = NSSelectorFromString(@"didFinishPickingImageWithEditImageAttr:");
            Method m = class_getInstanceMethod(pickerCls, pickSel);
            if (m) {
                NSLog(@"[bgce] MMImagePickerController hook成功");
            }
        }

        // 悬浮按钮
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                static dispatch_once_t once;
                dispatch_once(&once, ^{
                    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
                    btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 60,
                                           [UIScreen mainScreen].bounds.size.height - 220, 44, 44);
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ WXInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ WXInstall(); }];
}
