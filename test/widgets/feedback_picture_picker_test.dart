import 'package:chessever2/widgets/review_prompt/direct_feedback_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(feedbackMediaPickerChannel, null);
  });

  test('reads a photo-library image from the native media picker', () async {
    messenger.setMockMethodCallHandler(feedbackMediaPickerChannel, (call) async {
      expect(call.method, 'pickImage');
      return <String, Object?>{
        'bytes': Uint8List.fromList(const [9, 8, 7]),
        'fileName': 'library.jpg',
      };
    });

    final picture = await pickFeedbackPicture();

    expect(picture?.fileName, 'library.jpg');
    expect(picture?.bytes, Uint8List.fromList(const [9, 8, 7]));
  });

  test('returns null when the photo library is cancelled', () async {
    messenger.setMockMethodCallHandler(feedbackMediaPickerChannel, (call) async {
      return null;
    });

    expect(await pickFeedbackPicture(), isNull);
  });

  test('maps a native permission denial', () async {
    messenger.setMockMethodCallHandler(feedbackMediaPickerChannel, (call) async {
      throw PlatformException(code: 'PERMISSION_DENIED');
    });

    expect(
      pickFeedbackPicture(),
      throwsA(isA<FeedbackPicturePermissionDeniedException>()),
    );
  });

  test('rejects pictures larger than 8 MB', () async {
    messenger.setMockMethodCallHandler(feedbackMediaPickerChannel, (call) async {
      return <String, Object?>{
        'bytes': Uint8List(8 * 1024 * 1024 + 1),
        'fileName': 'huge.jpg',
      };
    });

    expect(pickFeedbackPicture(), throwsA(isA<FeedbackPictureTooLargeException>()));
  });
}
