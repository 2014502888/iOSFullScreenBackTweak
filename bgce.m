#import <UIKit/UIKit.h>
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
    // 调试:扫描所有类,找实现了关键方法的类名
    [ac addAction:[UIAlertAction actionWithTitle:@"调试: 扫描Hook类名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSMutableString *result = [NSMutableString string];
        unsigned int total = 0;
        Class *classes = objc_copyClassList(&total);
        NSArray *sels = @[@"openVideoWindowWithContact:msgWrap:isCaller:from:",
                          @"openAudioWindowWithContact:msgWrap:isCaller:from:",
                          @"onOpenMyFavoritesListController",
                          @"didFinishPickingImageWithEditImageAttr:"];
        for (NSString *selName in sels) {
            [result appendFormat:@"【%@】\n", selName];
            BOOL found = NO;
            SEL sel = NSSelectorFromString(selName);
            for (unsigned int i = 0; i < total; i++) {
                if (class_getInstanceMethod(classes[i], sel)) {
                    [result appendFormat:@"  %@\n", NSStringFromClass(classes[i])];
                    found = YES;
                }
            }
            if (!found) [result appendFormat:@"  (未找到)\n"];
            [result appendString:@"\n"];
        }
        free(classes);
        UIViewController *t = WXTopVC();
        UIAlertController *dbg = [UIAlertController alertControllerWithTitle:@"扫描结果" message:result preferredStyle:UIAlertControllerStyleAlert];
        [dbg addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        [t presentViewController:dbg animated:YES completion:nil];
    }]];
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
        // hook MMUIViewController(微信所有页面的基类)
        Class baseCls = NSClassFromString(@"MMUIViewController");
        if (baseCls) {
            Method m = class_getInstanceMethod(baseCls, @selector(viewDidAppear:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, BOOL animated) {
                    ((void(*)(id, SEL, BOOL))orig)(self, @selector(viewDidAppear:), animated);
                    @try {
                        NSString *clsName = NSStringFromClass([self class]);
                        UIView *v = [(UIViewController *)self view];
                        if (!v) return;

                        // 通话页面:加美颜按钮
                        if (WXGet(kWXKeyBeauty) &&
                            ([clsName containsString:@"Voip"] || [clsName containsString:@"Call"] || [clsName containsString:@"VideoChat"] || [clsName containsString:@"Talk"])) {
                            for (UIView *sv in v.subviews) { if (sv.tag == 99999) return; }
                            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
                            b.frame = CGRectMake(16, 80, 44, 44);
                            b.layer.cornerRadius = 22;
                            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
                            [b setTitle:@"美" forState:UIControlStateNormal];
                            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                            b.tag = 99999;
                            [v addSubview:b];
                        }

                        // 收藏上锁:在"我"页面找收藏cell隐藏
                        if (WXGet(kWXKeyFavLock) &&
                            ([clsName containsString:@"Setting"] || [clsName containsString:@"MainPage"] || [clsName containsString:@"Mine"])) {
                            for (UIView *sv in v.subviews) {
                                if ([sv isKindOfClass:[UITableView class]]) {
                                    UITableView *tv = (UITableView *)sv;
                                    for (UITableViewCell *cell in tv.visibleCells) {
                                        if ([cell.textLabel.text containsString:@"收藏"]) {
                                            cell.hidden = YES;
                                            cell.alpha = 0.0;
                                        }
                                    }
                                }
                            }
                        }
                    } @catch (__unused NSException *e) {}
                }));
            }
        }

        // 拨号静音:hook AVAudioSession,通话时设为只录音
        Class sesCls = NSClassFromString(@"AVAudioSession");
        if (sesCls) {
            Method m = class_getInstanceMethod(sesCls, @selector(setCategory:error:));
            if (m) {
                __block IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^(id self, NSString *cat, NSError **err) {
                    if (WXGet(kWXKeyMuteRingtone) &&
                        ([cat isEqualToString:@"AVAudioSessionCategoryPlayAndRecord"] || [cat isEqualToString:@"AVAudioSessionCategoryRecord"])) {
                        // 保持静音模式,不播放拨号音
                    }
                    ((void(*)(id, SEL, NSString *, NSError **))orig)(self, @selector(setCategory:error:), cat, err);
                }));
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ WXInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ WXInstall(); }];
}
