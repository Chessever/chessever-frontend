import 'package:flutter/foundation.dart';

const int kMaximumSavedStudyReferences = 48;
const int kMaximumSavedStudiesRailItems = 12;
const int kSavedStudyResolutionConcurrency = 4;

final RegExp _canonicalLichessStudyId = RegExp(r'^[A-Za-z0-9]{8}$');
final RegExp _canonicalLichessChapterId = RegExp(r'^[A-Za-z0-9]{1,64}$');
final RegExp _gamebaseStudyContentVersion = RegExp(r'^sha256:[0-9a-f]{64}$');

String normalizeLichessStudyId(String value) {
  final normalized = value.trim();
  if (!_canonicalLichessStudyId.hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'lichessStudyId',
      'Must be an eight-character canonical Lichess Study ID.',
    );
  }
  return normalized;
}

String? normalizeLichessChapterId(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (!_canonicalLichessChapterId.hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'lichessChapterId',
      'Must be a canonical Lichess chapter ID.',
    );
  }
  return normalized;
}

String? normalizeStudyContentVersion(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (!_gamebaseStudyContentVersion.hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'contentVersion',
      'Must be a canonical lowercase Gamebase sha256 content version.',
    );
  }
  return normalized;
}

@immutable
class StudyBookmarkDisplaySnapshot {
  const StudyBookmarkDisplaySnapshot({
    this.title,
    this.authorUsername,
    this.attribution,
  });

  final String? title;
  final String? authorUsername;
  final String? attribution;

  bool get isEmpty =>
      title == null && authorUsername == null && attribution == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (title != null) 'title': title,
    if (authorUsername != null) 'author_username': authorUsername,
    if (attribution != null) 'attribution': attribution,
  };

  factory StudyBookmarkDisplaySnapshot.fromJson(Object? value) {
    if (value == null) return const StudyBookmarkDisplaySnapshot();
    if (value is! Map) {
      throw const FormatException('display_snapshot must be a JSON object.');
    }
    final json = Map<String, dynamic>.from(value);
    const allowed = <String>{'title', 'author_username', 'attribution'};
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('display_snapshot contains unknown fields.');
    }
    return StudyBookmarkDisplaySnapshot(
      title: _optionalSafeText(json['title'], 'title', 240),
      authorUsername: _optionalSafeText(
        json['author_username'],
        'author_username',
        80,
      ),
      attribution: _optionalSafeText(json['attribution'], 'attribution', 320),
    );
  }

  static StudyBookmarkDisplaySnapshot validated({
    String? title,
    String? authorUsername,
    String? attribution,
  }) {
    return StudyBookmarkDisplaySnapshot(
      title: _normalizeOptionalSafeText(title, 'title', 240),
      authorUsername: _normalizeOptionalSafeText(
        authorUsername,
        'authorUsername',
        80,
      ),
      attribution: _normalizeOptionalSafeText(attribution, 'attribution', 320),
    );
  }
}

@immutable
class StudyBookmarkReference {
  const StudyBookmarkReference({
    required this.userId,
    required this.lichessStudyId,
    required this.displaySnapshot,
    required this.bookmarkedAt,
    required this.updatedAt,
    this.lichessChapterId,
    this.lastPly,
    this.contentVersion,
    this.progressUpdatedAt,
  });

  final String userId;
  final String lichessStudyId;
  final String? lichessChapterId;
  final int? lastPly;
  final String? contentVersion;
  final StudyBookmarkDisplaySnapshot displaySnapshot;
  final DateTime bookmarkedAt;
  final DateTime? progressUpdatedAt;
  final DateTime updatedAt;

  DateTime get recentActivityAt => progressUpdatedAt ?? bookmarkedAt;
  bool get hasProgress => lichessChapterId != null && lastPly != null;

  Uri get canonicalSourceUrl => Uri(
    scheme: 'https',
    host: 'lichess.org',
    pathSegments: <String>[
      'study',
      lichessStudyId,
      if (lichessChapterId != null) lichessChapterId!,
    ],
  );
}

String? _normalizeOptionalSafeText(
  String? value,
  String field,
  int maximumLength,
) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maximumLength) {
    throw ArgumentError.value(
      value,
      field,
      'Must contain between 1 and $maximumLength characters.',
    );
  }
  return normalized;
}

String? _optionalSafeText(Object? value, String field, int maximumLength) {
  if (value == null) return null;
  if (value is! String ||
      value.isEmpty ||
      value.length > maximumLength ||
      value.trim() != value) {
    throw FormatException('$field is not a safe display string.');
  }
  return value;
}
