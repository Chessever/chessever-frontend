import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _Callback = Void Function(Pointer<Utf8>);

/// Observes the existing FlutterWatch delegate rather than replacing the
/// process-global UNUserNotificationCenter delegate. Foreground and cold taps
/// use the same push callback; the host replays taps received before Dart starts.
class ChesseverWatchBridge {
  static void registerWith() {}

  static int Function()? _powerState;

  /// True when watchOS asks apps to do less: Low Power Mode is on, or the
  /// device is at a serious or critical thermal state. Reads live each call,
  /// so a change takes effect on the next poll.
  static bool get powerConstrained {
    try {
      final state = (_powerState ??= DynamicLibrary.process()
          .lookupFunction<Int32 Function(), int Function()>(
            'chessever_watch_power_state',
          ))();
      return state & 1 == 1 || (state >> 1) >= 2;
    } on ArgumentError {
      return false; // Symbol absent: not the watch host.
    }
  }

  static void Function(int, Pointer<Uint8>, int)? _soundLoad;
  static void Function(int)? _soundPlay;
  static void Function()? _soundStop;

  /// Hands the host a sound file's bytes under [sound], ready for
  /// [playSound]. False off the watch host (the symbol is absent).
  static bool loadSound(int sound, List<int> bytes) {
    if (bytes.isEmpty) return false;
    try {
      _soundLoad ??= DynamicLibrary.process()
          .lookupFunction<
            Void Function(Int32, Pointer<Uint8>, Int32),
            void Function(int, Pointer<Uint8>, int)
          >('chessever_watch_sound_load');
    } on ArgumentError {
      return false;
    }
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      // The host copies the bytes before returning.
      _soundLoad!(sound, buffer, bytes.length);
    } finally {
      malloc.free(buffer);
    }
    return true;
  }

  /// Plays a sound handed over by [loadSound]; nothing when it was not.
  static void playSound(int sound) {
    try {
      (_soundPlay ??= DynamicLibrary.process()
          .lookupFunction<Void Function(Int32), void Function(int)>(
            'chessever_watch_sound_play',
          ))(sound);
    } on ArgumentError {
      // Not the watch host.
    }
  }

  static void stopSounds() {
    try {
      (_soundStop ??= DynamicLibrary.process()
          .lookupFunction<Void Function(), void Function()>(
            'chessever_watch_sound_stop',
          ))();
    } on ArgumentError {
      // Not the watch host.
    }
  }

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  NativeCallable<_Callback>? _callback;
  void Function()? _stop;
  void Function(Pointer<Utf8>)? _free;
  Stream<Map<String, dynamic>> get taps => _events.stream;

  void start() {
    final library = DynamicLibrary.process();
    _free = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('chessever_watch_free');
    _stop = library.lookupFunction<Void Function(), void Function()>(
      'chessever_watch_stop',
    );
    void onTap(Pointer<Utf8> pointer) {
      try {
        final json = jsonDecode(pointer.toDartString());
        if (json is Map && !_events.isClosed) {
          _events.add(Map<String, dynamic>.from(json));
        }
      } finally {
        _free!(pointer);
      }
    }

    _callback = NativeCallable<_Callback>.listener(onTap);
    library.lookupFunction<
      Void Function(Pointer<NativeFunction<_Callback>>),
      void Function(Pointer<NativeFunction<_Callback>>)
    >('chessever_watch_listen')(_callback!.nativeFunction);
  }

  Future<void> dispose() async {
    _stop?.call();
    // Native stop is synchronous. Already-enqueued callbacks still own their
    // strings and run before closing the listener on the next event loop turn.
    await Future<void>.delayed(Duration.zero);
    _callback?.close();
    await _events.close();
  }
}
