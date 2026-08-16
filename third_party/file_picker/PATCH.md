# Vendored file_picker — ChessEver patch

This is the `file_picker` pub package, vendored only so we can carry a small
**iOS build-manifest** patch. It is wired in via the app's `pubspec.yaml`:

```yaml
dependency_overrides:
  file_picker:
    path: third_party/file_picker
```

No Dart code is changed. The only edits are to the two iOS manifests.
The upstream `example/` and `test/` directories are not vendored.

## Current vendored version

`8.3.7` (copied from `~/.pub-cache/hosted/pub.dev/file_picker-8.3.7`).

## The patch — compile the iOS plugin as document-picker-only

**Files:** `ios/file_picker/Package.swift`, `ios/file_picker.podspec`
**Fixes:** `ITMS-90683: Missing purpose string in Info.plist —
NSCameraUsageDescription` on every App Store upload from build 3338 onward.

### Root cause

`FilePickerPlugin.m` guards its three pickers behind `PICKER_MEDIA`,
`PICKER_AUDIO` and `PICKER_DOCUMENT`. Upstream's **`Package.swift` defines all
three unconditionally** and takes a hard dependency on the whole
`DKImagePickerController` product, which in turn pulls in **`DKCamera`**
(`AVCaptureDevice`, live camera UI), `DKPhotoGallery`, `TOCropViewController`,
`SDWebImage` and `SwiftyGif`. `PICKER_AUDIO` likewise compiles in
`MPMediaPickerController` (Apple Music library).

Two things then combined into the upload rejection:

1. The **podspec** only ever pulled the narrower `DKImagePickerController/PhotoGallery`
   subspec, which does *not* include `DKCamera`. `Package.swift` has no such
   narrowing, so moving the plugin graph onto SPM in `34.5.3` (`c25a561d`) added
   the camera code to the build for the first time.
2. SPM **static-links** plugin code into the Runner executable, where CocoaPods
   `use_frameworks!` gave each plugin its own dynamic framework. So the API
   reference is now attributed to `Runner.app` and Apple demands the purpose
   string in *our* `Info.plist`.

ChessEver only calls `FilePicker.platform.pickFiles(type: FileType.custom,
allowedExtensions: ['pgn'])` with a `FileType.any` fallback — both are pure
`UIDocumentPickerViewController` paths. The media and audio pickers have no call
site here and never had one.

### The change

Both manifests now define **`PICKER_DOCUMENT` only** and declare **no**
`DKImagePickerController` dependency:

```swift
dependencies: [],
targets: [
    .target(
        name: "file_picker",
        dependencies: [],
        resources: [.process("PrivacyInfo.xcprivacy")],
        cSettings: [
            .headerSearchPath("include/file_picker"),
            .define("PICKER_DOCUMENT")
        ]
    )
]
```

`FilePickerPlugin.h` already guards every media/audio protocol conformance behind
those same macros, so the plugin compiles clean and drops `AVCaptureDevice`,
`UIImagePickerController` and `MPMediaPickerController` from the binary. If some
future code does ask for `FileType.image` / `.video` / `.media` / `.audio`, the
plugin returns upstream's explicit "Support for the ... picker is not compiled
in" `FlutterError` rather than crashing — that is the signal to revisit this
patch, not to paper over it.

The podspec is patched to match so the CocoaPods fallback path links the same
API surface as the SPM path.

## How to bump to a newer file_picker

1. `flutter pub get` with the new `file_picker:` constraint so it lands in the
   pub cache.
2. `rm -rf third_party/file_picker && rsync -a --exclude 'example/' ~/.pub-cache/hosted/pub.dev/file_picker-<new>/ third_party/file_picker/ && chmod -R u+w third_party/file_picker && rm -rf third_party/file_picker/test`
3. Reapply the two manifest edits above.
4. Update the "Current vendored version" line here.
5. `flutter pub get && flutter analyze --no-pub lib`.

**Drop this override entirely** once `file_picker` 12.x is stable: its rewritten
darwin implementation has no `DKImagePickerController` dependency at all
(verified in `12.0.0-beta.5`), which makes this patch unnecessary.
