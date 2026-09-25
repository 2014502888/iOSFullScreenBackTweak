#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSMutableArray *gCalledMethods = nil;

static void WXLogMethod(NSString *methodName) {
    if (!gCalledMethods) gCalledMethods = [NSMutableArray array];
    [gCalledMethods addObject:methodName];
}

static void WXInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class moreCls = NSClassFromString(@"MoreViewController");
        if (!moreCls) return;
        
        // 遍历MoreViewController的所有方法
        unsigned int count = 0;
        Method *methods = class_copyMethodList(moreCls, &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *selName = NSStringFromSelector(sel);
            // 只hook跟Favor/收藏/open/push相关的方法
            if (![selName containsString:@"Favor"] && ![selName containsString:@"favor"] && 
                ![selName containsString:@"open"] && ![selName containsString:@"Open"] &&
                ![selName containsString:@"push"] && ![selName containsString:@"Push"]) {
                continue;
            }
            
            Method m = methods[i];
            __block IMP orig = method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^(id self, ...) {
                WXLogMethod(selName);
                // 调用原方法
                va_list args;
                va_start(args, self);
                // 简单调用,不处理返回值
                void (*func)(id, SEL, va_list) = (void *)orig;
                func(self, sel, args);
                va_end(args);
                
                // 弹调试弹窗
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIViewController *vc = (UIViewController *)self;
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"调用了方法" message:selName preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [vc presentViewController:alert animated:YES completion:nil];
                });
            }));
        }
        free(methods);
    });
}

__attribute__((constructor)) static void WXConstructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WXInstall(); });
}