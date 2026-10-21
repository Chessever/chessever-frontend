import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:flutter/foundation.dart';
import 'package:chessever2/services/feedback_relay.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// The account behind a piece of feedback, so a report can be traced back to
/// the person who sent it and answered.
class FeedbackSender {
  const FeedbackSender({
    required this.userId,
    this.name,
    this.email,
    this.signIn,
    this.lichessUsername,
    this.chesscomUsername,
  });

  /// Reads the signed-in Supabase user. Null when nobody is signed in.
  static FeedbackSender? fromUser(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata;
    final email = user.email?.trim();
    return FeedbackSender(
      userId: user.id,
      name:
          AppUser.metadataUsername(metadata, 'full_name') ??
          AppUser.metadataUsername(metadata, 'name'),
      email: email == null || email.isEmpty ? null : email,
      signIn: user.isAnonymous
          ? 'anonymous'
          : user.appMetadata['provider']?.toString(),
      lichessUsername: AppUser.metadataUsername(
        metadata,
        kLichessUsernameMetadataKey,
      ),
      chesscomUsername: AppUser.metadataUsername(
        metadata,
        kChesscomUsernameMetadataKey,
      ),
    );
  }

  final String userId;
  final String? name;
  final String? email;
  final String? signIn;
  final String? lichessUsername;
  final String? chesscomUsername;
}

/// [sender] is required, null included, so no caller can drop the account
/// by omission: sidebar reports shipped without a user ID until 36.10.6.
String buildDirectFeedbackMessage({
  required String feedback,
  required String source,
  required FeedbackSender? sender,
  String? appVersion,
  String? platform,
}) {
  final buffer = StringBuffer()
    ..writeln('📣 New App Feedback')
    ..writeln()
    ..writeln('Source: $source')
    ..writeln('Platform: ${platform ?? 'Unknown'}')
    ..writeln('Version: ${appVersion ?? 'Unknown'}')
    ..writeln();
  // The account sits above the message so the 1024-character document
  // caption limit can only ever trim the feedback text, never the user ID.
  if (sender == null) {
    buffer.writeln('User ID: Not signed in');
  } else {
    buffer.writeln('User ID: ${sender.userId}');
    for (final (label, value) in [
      ('Name', sender.name),
      ('Email', sender.email),
      ('Sign-in', sender.signIn),
      ('Lichess', sender.lichessUsername),
      ('Chess.com', sender.chesscomUsername),
    ]) {
      if (value != null) buffer.writeln('$label: $value');
    }
  }
  return (buffer
        ..writeln()
        ..writeln('Message:')
        ..writeln(feedback))
      .toString();
}

/// Telegram rejects an empty document name and treats a path as the filename.
/// Keep a real basename with an extension so sendDocument stays valid.
String documentFileName(String? name) {
  final base = (name ?? '').trim().split(RegExp(r'[/\\]')).last;
  if (base.isEmpty) return 'feedback-picture.jpg';
  if (base.contains('.')) return base;
  return '$base.jpg';
}

/// Sends feedback through the server relay; no Telegram credential is shipped.
class TelegramNotificationService {
  TelegramNotificationService({FeedbackRelay? relay})
    : _relay = relay ?? FeedbackRelay();
  static final TelegramNotificationService instance =
      TelegramNotificationService();
  final FeedbackRelay _relay;

  Future<bool> sendDirectFeedbackNotification({
    required String feedback,
    required String source,
    required FeedbackSender? sender,
    String? appVersion,
    String? platform,
    Uint8List? pictureBytes,
    String? pictureFileName,
  }) => _relay.send(
    buildDirectFeedbackMessage(
      feedback: feedback,
      source: source,
      sender: sender,
      appVersion: appVersion,
      platform: platform,
    ),
    picture: pictureBytes,
  );

  Future<bool> sendFeedbackNotification({
    required int rating,
    required String feedback,
    required String source,
    String? userId,
    String? appVersion,
    String? platform,
  }) {
    final safeRating = rating.clamp(0, 5);
    final message = StringBuffer()
      ..writeln('New App Feedback')
      ..writeln('Rating: $safeRating/5')
      ..writeln('Source: $source')
      ..writeln('Platform: ${platform ?? 'Unknown'}')
      ..writeln('Version: ${appVersion ?? 'Unknown'}')
      ..writeln('User ID: ${userId ?? 'Anonymous'}')
      ..writeln()
      ..writeln(feedback);
    return _relay.send(message.toString());
  }
}
