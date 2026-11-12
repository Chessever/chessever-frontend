#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <AVFoundation/AVFoundation.h>
#import <WatchKit/WatchKit.h>
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

// Power budget for live polling. Bit 0: Low Power Mode is on. Bits 1-2:
// NSProcessInfoThermalState (0 nominal, 1 fair, 2 serious, 3 critical).
EXPORT int32_t chessever_watch_power_state(void) {
  NSProcessInfo *info = NSProcessInfo.processInfo;
  int32_t state = info.isLowPowerModeEnabled ? 1 : 0;
  return state | ((int32_t)info.thermalState << 1);
}

// Board sounds: the phone's own sound files, handed over once as bytes and
// kept ready to play. Ambient leaves mixing, routing and muting to watchOS;
// clips only play while the game and app are active.
static NSMutableDictionary<NSNumber *, AVAudioPlayer *> *soundPlayers;

EXPORT void chessever_watch_sound_load(int32_t sound, const uint8_t *bytes, int32_t length) {
  if (bytes == NULL || length <= 0) return;
  // Copied now: the caller frees its buffer as soon as this returns.
  NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!soundPlayers) {
      NSError *error = nil;
      if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&error]) {
        NSLog(@"ChessEver watch sound session: %@", error);
        return;
      }
      soundPlayers = [NSMutableDictionary dictionary];
    }
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:data error:&error];
    if (!player) {
      NSLog(@"ChessEver watch sound %d: %@", sound, error);
      return;
    }
    [player prepareToPlay];
    soundPlayers[@(sound)] = player;
  });
}

EXPORT void chessever_watch_sound_play(int32_t sound) {
  dispatch_async(dispatch_get_main_queue(), ^{
    // Recheck on the main queue: the wrist may have lowered after Dart sent it.
    if ([WKApplication sharedApplication].applicationState != WKApplicationStateActive) return;
    AVAudioPlayer *player = soundPlayers[@(sound)];
    if (!player) return;
    // Fast review must not layer a capture over the previous move's clip.
    for (AVAudioPlayer *other in soundPlayers.allValues) {
      if (other != player && other.isPlaying) [other pause];
    }
    player.currentTime = 0;
    [player play];
  });
}

EXPORT void chessever_watch_sound_stop(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    for (AVAudioPlayer *player in soundPlayers.allValues) [player pause];
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
  });
}
