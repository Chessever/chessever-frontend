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
