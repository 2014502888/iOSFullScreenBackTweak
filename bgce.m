#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AudioToolbox/AudioToolbox.h>

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

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{

        // === 1. 收藏上锁: hook MMUIViewController基类,在"我"页面隐藏收藏cell ===
        Class baseCls = NSClassFromString(@"MMUIViewController");
        if (baseCls) {
            Method m = class_getInstanceMethod(baseCls, @selector(viewDidAppear:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
                    ((void(*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
                    @try {
                        if (!WXGet(kWXKeyFavLock)) return;
                        UIView *v = [(UIViewController *)self view];
                        if (!v) return;
                        // 遍历所有subview找tableView
                        for (UIView *sv in v.subviews) {
                            if ([sv isKindOfClass:[UITableView class]]) {
                                UITableView *tv = (UITableView *)sv;
                                for (UITableViewCell *cell in tv.visibleCells) {
                                    if ([cell.textLabel.text containsString:@"收藏"]) {
                                        cell.hidden = YES;
                                        cell.alpha = 0.0;
                                        // 找下一个cell补位
                                        NSIndexPath *ip = [tv indexPathForCell:cell];
                                        if (ip && ip.row + 1 < [tv numberOfRowsInSection:ip.section]) {
                                            NSIndexPath *next = [NSIndexPath indexPathForRow:ip.row+1 inSection:ip.section];
                                            [tv insertRowsAtIndexPaths:@[next] withRowAnimation:UITableViewRowAnimationNone];
                                        }
                                    }
                                }
                            }
                        }
                    } @catch (__unused NSException *e) {}
                }));
            }
        }

        // === 2. 拨号静音: hook AVAudioPlayer,所有播放音量设为0 ===
        Class audioPlayerCls = NSClassFromString(@"AVAudioPlayer");
        if (audioPlayerCls) {
            Method m = class_getInstanceMethod(audioPlayerCls, @selector(play));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self) {
                    ((void(*)(id, SEL))orig)(self, @selector(play));
                    if (WXGet(kWXKeyMuteRingtone)) {
                        @try { [self setValue:@0.0 forKey:@"volume"]; } @catch (__unused NSException *e) {}
                    }
                }));
            }
        }

        // === 3. 通话镜像: hook AVCaptureVideoPreviewLayer ===
        Class layerCls = NSClassFromString(@"AVCaptureVideoPreviewLayer");
        if (layerCls) {
            Method m = class_getInstanceMethod(layerCls, @selector(setMirrored:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL mirrored) {
                    if (WXGet(kWXKeyMirror)) mirrored = YES;
                    ((void(*)(id, SEL, BOOL))orig)(self, @selector(setMirrored:), mirrored);
                }));
            }
        }

        // === 4. 快捷发送编辑图片: hook MMImagePickerController ===
        Class pickerCls = NSClassFromString(@"MMImagePickerController");
        if (pickerCls) {
            SEL sel = NSSelectorFromString(@"didFinishPickingImageWithEditImageAttr:");
            Method m = class_getInstanceMethod(pickerCls, sel);
            if (m) {
                // 这个方法存在,等后续实现编辑器
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
