// Keep the shared phone entrypoint compilable on platforms without dart:ffi.
export 'src/bridge_stub.dart'
    if (dart.library.ffi) 'src/bridge_native.dart'
    show ChesseverWatchBridge;
