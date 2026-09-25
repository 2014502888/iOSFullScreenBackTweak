#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ==================== 设置存储 ====================
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

// ==================== 悬浮设置按钮 ====================
static UIViewController *WXTopVC(void) {
    UIWindowScene *ws = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { ws = s; break; }
    }
    if (!ws) return nil;
    UIViewController *vc = ws.windows.firstObject.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
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
    [ac addAction:[UIAlertAction actionWithTitle:mu ? @"✓ 来电静音铃声: 开" : @"  来电静音铃声: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyMuteRingtone, !mu); }]];

    BOOL fl = WXGet(kWXKeyFavLock);
    [ac addAction:[UIAlertAction actionWithTitle:fl ? @"✓ 收藏上锁: 开" : @"  收藏上锁: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyFavLock, !fl); }]];

    BOOL qe = WXGet(kWXKeyQuickEdit);
    [ac addAction:[UIAlertAction actionWithTitle:qe ? @"✓ 快捷发送编辑图片: 开" : @"  快捷发送编辑图片: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ WXSet(kWXKeyQuickEdit, !qe); }]];

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

// ==================== 1. 通话美颜 ====================
static void WXBeauty_Hook(void) {
    Class voipCls = NSClassFromString(@"VoipView");
    if (!voipCls) voipCls = NSClassFromString(@"MMVoipViewController");
    if (!voipCls) return;

    SEL origSel = @selector(viewDidAppear:);
    Method origMethod = class_getInstanceMethod(voipCls, origSel);
    if (!origMethod) return;

    __block IMP origImp = method_getImplementation(origMethod);
    void (^block)(id, BOOL) = ^(id self, BOOL animated) {
        ((void(*)(id, SEL, BOOL))origImp)(self, origSel, animated);
        if (!WXGet(kWXKeyBeauty)) return;
        @try {
            UIView *view = [(UIViewController *)self view];
            if (!view) return;
            for (UIView *sv in view.subviews) {
                if (sv.tag == 99999) return;
            }
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            btn.frame = CGRectMake(16, 80, 44, 44);
            btn.layer.cornerRadius = 22;
            btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
            [btn setTitle:@"美" forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.tag = 99999;
            [view addSubview:btn];
        } @catch (__unused NSException *e) {}
    };
    IMP newImp = imp_implementationWithBlock(block);
    method_setImplementation(origMethod, newImp);
}

// ==================== 2. 通话镜像 ====================
static void WXMirror_Hook(void) {
    Class voipCls = NSClassFromString(@"VoipView");
    if (!voipCls) return;
    SEL sel = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(voipCls, sel);
    if (!m) return;
    __block IMP origImp = method_getImplementation(m);
    void (^block)(id) = ^(id self) {
        ((void(*)(id, SEL))origImp)(self, sel);
        if (!WXGet(kWXKeyMirror)) return;
        @try {
            for (UIView *sv in [(UIView *)self subviews]) {
                if ([sv isKindOfClass:NSClassFromString(@"MTLLayer")] || sv.layer) {
                    sv.transform = CGAffineTransformMakeScale(-1.0, 1.0);
                }
            }
        } @catch (__unused NSException *e) {}
    };
    IMP newImp = imp_implementationWithBlock(block);
    method_setImplementation(m, newImp);
}

// ==================== 3. 来电静音铃声 ====================
static void WXMuteRingtone_Hook(void) {
    Class playerCls = NSClassFromString(@"AVAudioPlayer");
    if (!playerCls) return;
    SEL sel = @selector(play);
    Method m = class_getInstanceMethod(playerCls, sel);
    if (!m) return;
    __block IMP origImp = method_getImplementation(m);
    void (^block)(id) = ^(id self) {
        if (!WXGet(kWXKeyMuteRingtone)) {
            ((void(*)(id, SEL))origImp)(self, sel);
            return;
        }
        NSString *url = [(AVAudioPlayer *)self valueForKey:@"url"];
        if (url && ([url containsString:@"ring"] || [url containsString:@"Ring"] || [url containsString:@"call"])) {
            ((void(*)(id, SEL))origImp)(self, sel);
            [(AVAudioPlayer *)self setVolume:0.0];
        } else {
            ((void(*)(id, SEL))origImp)(self, sel);
        }
    };
    IMP newImp = imp_implementationWithBlock(block);
    method_setImplementation(m, newImp);
}

// ==================== 4. 收藏上锁 ====================
static void WXFavLock_Hook(void) {
    Class meCls = NSClassFromString(@"MMSystemSettingViewController");
    if (!meCls) meCls = NSClassFromString(@"WCTMainPageViewController");
    if (!meCls) return;
    SEL sel = @selector(tableView:cellForRowAtIndexPath:);
    Method m = class_getInstanceMethod(meCls, sel);
    if (!m) return;
    __block IMP origImp = method_getImplementation(m);
    void (^block)(id, UITableView *, NSIndexPath *) = ^(id self, UITableView *tv, NSIndexPath *ip) {
        UITableViewCell *cell = ((UITableViewCell *(*)(id, SEL, UITableView *, NSIndexPath *))origImp)(self, sel, tv, ip);
        if (!WXGet(kWXKeyFavLock)) return cell;
        @try {
            NSString *text = cell.textLabel.text;
            if (text && [text containsString:@"收藏"]) {
                cell.hidden = YES;
                cell.alpha = 0.0;
            }
        } @catch (__unused NSException *e) {}
        return cell;
    };
    IMP newImp = imp_implementationWithBlock(block);
    method_setImplementation(m, newImp);
}

// ==================== 5. 快捷发送编辑图片 ====================
static void WXQuickEdit_Hook(void) {
    Class pickerCls = NSClassFromString(@"MMImagePickerController");
    if (!pickerCls) return;
}

// ==================== 安装 ====================
static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        WXBeauty_Hook();
        WXMirror_Hook();
        WXMuteRingtone_Hook();
        WXFavLock_Hook();
        WXQuickEdit_Hook();

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
