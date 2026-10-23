#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#include <stdlib.h>
#include <string.h>

typedef void (*ChessEverTapCallback)(char *json);
static ChessEverTapCallback tapCallback;
static id tapObserver;
static id foregroundObserver;
#define EXPORT __attribute__((used, visibility("default")))

EXPORT void chessever_watch_listen(ChessEverTapCallback callback) {
  dispatch_async(dispatch_get_main_queue(), ^{
    tapCallback = callback;
    if (!tapObserver) {
      tapObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"FlutterWatchOSNotificationDidReceiveResponse"
        object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
          if (!tapCallback) return;
          NSString *action = notification.userInfo[@"actionIdentifier"];
          if (![action isEqualToString:UNNotificationDefaultActionIdentifier]) return;
          NSDictionary *payload = notification.userInfo[@"payload"];
          if (![payload isKindOfClass:[NSDictionary class]]) return;
          NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
          if (!data) return;
          NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          if (json) tapCallback(strdup(json.UTF8String));
        }];
      foregroundObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"FlutterWatchOSNotificationWillPresent"
        object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
          NSMutableDictionary *options = notification.userInfo[@"options"];
          options[@"options"] = @(UNNotificationPresentationOptionBanner |
              UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
        }];
    }
    [[NSNotificationCenter defaultCenter]
      postNotificationName:@"FlutterWatchOSRemoteNotificationObserversReady" object:nil];
  });
}

EXPORT void chessever_watch_stop(void) {
  void (^stop)(void) = ^{
    tapCallback = NULL;
    if (tapObserver) [[NSNotificationCenter defaultCenter] removeObserver:tapObserver];
    if (foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:foregroundObserver];
    tapObserver = nil;
    foregroundObserver = nil;
  };
  if ([NSThread isMainThread]) stop();
  else dispatch_sync(dispatch_get_main_queue(), stop);
}

EXPORT void chessever_watch_free(char *pointer) { free(pointer); }
