// swift-tools-version:5.9
// flutter-watchos discovers FFI plugins through this manifest: it compiles
// Classes/*.m into a static archive force-loaded into the watch binary and
// links the frameworks below. Without it the symbols are never bundled.

import PackageDescription

let package = Package(
    name: "chessever_watch_bridge",
    platforms: [
        .watchOS(.v7),
    ],
    products: [
        .library(name: "chessever-watch-bridge", targets: ["chessever_watch_bridge"]),
    ],
    targets: [
        .target(
            name: "chessever_watch_bridge",
            path: "Classes",
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
