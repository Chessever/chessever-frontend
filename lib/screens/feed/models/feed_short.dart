import 'package:flutter/foundation.dart';

@immutable
class FeedShort {
  const FeedShort._(this.id, this.title, this.channelName, this.thumbnail);

  final String id;
  final String title;
  final String channelName;
  final Uri? thumbnail;

  Uri get watchUrl => Uri.https('www.youtube.com', '/shorts/$id');

  static FeedShort? fromJson(Object? value) {
    if (value case {
      'type': 'short',
      'id': final String id,
      'title': final String title,
      'channelName': final String channelName,
    }) {
      if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
          title.trim().isEmpty ||
          channelName.trim().isEmpty) {
        return null;
      }
      final raw = (value as Map)['thumbnailUrl'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      final thumbnail =
          uri != null &&
              uri.scheme == 'https' &&
              uri.host == 'i.ytimg.com' &&
              uri.port == 443 &&
              uri.userInfo.isEmpty
          ? uri
          : null;
      return FeedShort._(id, title, channelName, thumbnail);
    }
    return null;
  }
}
