/// An editorial message: a title, a body that is plain text or Markdown
/// (never HTML), at most one attached image, and at most one button that
/// opens a link.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.readAt,
    this.isMarkdown = false,
    this.imageUrl,
    this.actionLabel,
    this.actionUrl,
  });

  final String id;
  final String title;
  final String body;
  final DateTime publishedAt;
  final DateTime? readAt;

  /// Whether [body] is rendered as Markdown; otherwise it is shown literally.
  final bool isMarkdown;

  /// The attached image, as the server sent it. What may actually be loaded
  /// is decided where it is drawn (see `inboxImageUri`).
  final String? imageUrl;

  /// The words on the message's button, and where it leads. Both or neither.
  final String? actionLabel;
  final String? actionUrl;

  bool get isUnread => readAt == null || readAt!.isBefore(publishedAt);

  /// [body] as running text for a one-glance preview: Markdown marks taken
  /// off, pictures dropped, links reduced to their words, on one line.
  String get previewText {
    var text = body;
    if (isMarkdown) {
      text = text
          .replaceAll(_fence, ' ')
          .replaceAll(_image, ' ')
          .replaceAllMapped(_link, (m) => m[1] ?? '')
          .replaceAll(_blockMark, '')
          .replaceAll(_rule, ' ')
          .replaceAllMapped(_emphasis, (m) => m[2] ?? '')
          .replaceAll('`', '');
    }
    return text.replaceAll(_space, ' ').trim();
  }

  static final _space = RegExp(r'\s+');
  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})[^\n]*$', multiLine: true);
  static final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
  static final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
  static final _blockMark = RegExp(
    r'^ {0,3}(#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+)',
    multiLine: true,
  );
  static final _rule = RegExp(r'^ {0,3}([-*_] ?){3,}$', multiLine: true);
  static final _emphasis = RegExp(r'(\*\*|__|\*|_|~~)(?=\S)(.+?)(?<=\S)\1');

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
    // Both are optional: rows from before rich messages, and the original
    // listing RPC, carry neither. An unknown format is shown literally.
    final image = json['image_url'];
    final label = _text(json['action_label']);
    final link = _text(json['action_url']);
    final hasAction = label != null && link != null;
    return InboxMessage(
      id: id,
      title: title,
      body: body,
      publishedAt: DateTime.parse(json['published_at'] as String).toUtc(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String).toUtc(),
      isMarkdown: json['body_format'] == 'markdown',
      imageUrl: _text(image),
      actionLabel: hasAction ? label : null,
      actionUrl: hasAction ? link : null,
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'published_at': publishedAt.toUtc().toIso8601String(),
    'read_at': readAt?.toUtc().toIso8601String(),
    'body_format': isMarkdown ? 'markdown' : 'plain',
    'image_url': imageUrl,
    'action_label': actionLabel,
    'action_url': actionUrl,
  };

  InboxMessage withReadAt(DateTime value) => InboxMessage(
    id: id,
    title: title,
    body: body,
    publishedAt: publishedAt,
    readAt: value,
    isMarkdown: isMarkdown,
    imageUrl: imageUrl,
    actionLabel: actionLabel,
    actionUrl: actionUrl,
  );
}
