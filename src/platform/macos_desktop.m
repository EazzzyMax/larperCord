#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#include <stdio.h>

#import "macos.h"

static void (*larper_show_window)(void) = NULL;

static BOOL larper_reopen(id self, SEL selector, NSApplication *application, BOOL visible) {
    (void)self;
    (void)selector;
    (void)application;
    (void)visible;
    if (larper_show_window != NULL) larper_show_window();
    return YES;
}

void larper_macos_install_reopen(void (*show_window)(void)) {
    id delegate = [NSApp delegate];
    if (delegate == nil) return;
    Class delegate_class = object_getClass(delegate);
    SEL selector = @selector(applicationShouldHandleReopen:hasVisibleWindows:);
    // O delegate pertence ao SDL. Preserva um handler existente, inclusive
    // herdado, caso uma versão futura do SDL implemente o mesmo método.
    if (class_getInstanceMethod(delegate_class, selector) != NULL) return;
    char types[32];
    snprintf(types, sizeof(types), "%s@:@%s", @encode(BOOL), @encode(BOOL));
    if (class_addMethod(delegate_class, selector, (IMP)larper_reopen, types)) {
        larper_show_window = show_window;
    }
}

static void larper_enqueue_notification(UNUserNotificationCenter *center,
                                        UNMutableNotificationContent *content) {
    UNNotificationRequest *request =
        [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                              content:content
                                              trigger:nil];
    [center addNotificationRequest:request withCompletionHandler:nil];
}

void larper_macos_notify(const char *title, const char *body) {
    if (title == NULL || body == NULL) return;
    // O executável avulso serve para QA e ferramentas, sem pedir permissão.
    if ([[NSBundle mainBundle] bundleIdentifier] == nil) return;
    if (@available(macOS 10.14, *)) {
        NSString *notification_title = [[NSString alloc] initWithUTF8String:title];
        NSString *notification_body = [[NSString alloc] initWithUTF8String:body];
        if (notification_title == nil || notification_body == nil) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            static BOOL requested_authorization = NO;
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = notification_title;
            content.body = notification_body;
            content.sound = [UNNotificationSound defaultSound];

            if (!requested_authorization) {
                requested_authorization = YES;
                [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                       completionHandler:^(BOOL granted, NSError *error) {
                    (void)error;
                    if (granted) larper_enqueue_notification(center, content);
                }];
                return;
            }
            [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
                if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
                    settings.authorizationStatus == UNAuthorizationStatusProvisional) {
                    larper_enqueue_notification(center, content);
                }
            }];
        });
    }
}
