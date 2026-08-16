// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// PATCHED (see third_party/file_picker/PATCH.md): the media and audio pickers
// are compiled out. Upstream defines PICKER_MEDIA / PICKER_AUDIO / PICKER_DOCUMENT
// unconditionally here and pulls the whole DKImagePickerController product, which
// drags DKCamera (AVCaptureDevice) and MPMediaPickerController into the Runner
// binary. ChessEver only ever calls FileType.custom(['pgn']) / FileType.any, so
// PICKER_DOCUMENT alone covers every call site.

import PackageDescription

let package = Package(
    name: "file_picker",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "file-picker", targets: ["file_picker"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "file_picker",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("include/file_picker"),
                .define("PICKER_DOCUMENT")
            ]
        )
    ]
)
