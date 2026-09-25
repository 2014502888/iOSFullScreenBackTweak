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
            for (UIView *sv in view.subviews) { if (sv.tag == 99999) return; }
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
    method_setImplementation(origMethod, imp_implementationWithBlock(block));
}

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        WXBeauty_Hook();