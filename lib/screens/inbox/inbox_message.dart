/// Editorial content is plain text, never HTML, Markdown or a navigation target.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime publishedAt;
  final DateTime? readAt;
  bool get isUnread => readAt == null;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final title = json['title'] as String;
    final body = json['body'] as String;
    if (!_uuid.hasMatch(id) ||
        title.trim().isEmpty ||
        title.runes.length > 200 ||
        title.contains('\n') ||
        title.contains('\r') ||
        body.trim().isEmpty ||
        body.runes.length > 20000) {
      throw const FormatException('Invalid editorial message');
    }
    return InboxMessage(
      id: id,
      title: title,
      body: body,
      publishedAt: DateTime.parse(json['published_at'] as String).toUtc(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'published_at': publishedAt.toUtc().toIso8601String(),
    'read_at': readAt?.toUtc().toIso8601String(),
  };

  InboxMessage withReadAt(DateTime value) => InboxMessage(
    id: id,
    title: title,
    body: body,
    publishedAt: publishedAt,
    readAt: value,
  );
}
