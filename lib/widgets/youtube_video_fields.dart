import 'package:flutter/material.dart';
import '../utils/youtube_video.dart';

/// A URL and its editable playback settings always describe the same video.
class YoutubeVideoFields extends StatefulWidget {
  const YoutubeVideoFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  State<YoutubeVideoFields> createState() => _YoutubeVideoFieldsState();
}

class _YoutubeVideoFieldsState extends State<YoutubeVideoFields> {
  final _url = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _captionsLanguage = TextEditingController();
  final _playerLanguage = TextEditingController();
  bool _autoplay = false, _muted = false, _loop = false, _captions = false;
  bool _advanced = false;
  String? _error;
  String _lastEmitted = '';

  @override
  void initState() {
    super.initState();
    _read(widget.value);
  }

  @override
  void didUpdateWidget(covariant YoutubeVideoFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _lastEmitted) {
      _read(widget.value);
    }
  }

  void _read(String value) {
    _url.text = value;
    _error = null;
    try {
      final v = value.trim().isEmpty ? null : YoutubeVideo.parse(value);
      _start.text = v == null ? '' : YoutubeVideo.formatTime(v.start);
      _end.text = v?.end == null ? '' : YoutubeVideo.formatTime(v!.end!);
      _autoplay = v?.autoplay ?? false;
      _muted = v?.muted ?? false;
      _loop = v?.loop ?? false;
      _captions = v?.captions ?? false;
      _captionsLanguage.text = v?.captionLanguage ?? '';
      _playerLanguage.text = v?.playerLanguage ?? '';
    } on FormatException catch (e) {
      _error = e.message;
    }
  }

  String _value() {
    if (_url.text.trim().isEmpty) return '';
    final id = YoutubeVideo.parse(_url.text).id;
    final v = YoutubeVideo(
      id: id,
      start: _start.text.trim().isEmpty ? 0 : YoutubeVideo.time(_start.text),
      end: _end.text.trim().isEmpty ? null : YoutubeVideo.time(_end.text),
      autoplay: _autoplay,
      muted: _muted,
      loop: _loop,
      captions: _captions,
      captionLanguage: _captionsLanguage.text.trim(),
      playerLanguage: _playerLanguage.text.trim(),
    );
    return YoutubeVideo.parse(v.url.toString()).url.toString();
  }

  void _emit({bool fromUrl = false}) {
    if (fromUrl) _read(_url.text);
    try {
      final value = _value();
      _error = null;
      if (!fromUrl) _url.text = value;
      _lastEmitted = value;
      widget.onChanged(value);
    } on FormatException catch (e) {
      _error = e.message;
      // Keep invalid URL drafts visible; the parent Form refuses submission.
      if (fromUrl) {
        _lastEmitted = _url.text;
        widget.onChanged(_url.text);
      }
    }
    setState(() {});
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool url = false,
  }) => TextFormField(
    controller: controller,
    enabled: widget.enabled,
    keyboardType: url ? TextInputType.url : TextInputType.text,
    autocorrect: false,
    decoration: InputDecoration(labelText: label),
    validator: url
        ? (_) {
            try {
              _value();
              return null;
            } on FormatException catch (e) {
              return e.message;
            }
          }
        : null,
    onChanged: (_) => _emit(fromUrl: url),
  );

  Widget _flag(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: widget.enabled
            ? (v) {
                change(v ?? false);
                _emit();
              }
            : null,
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(_url, 'YouTube video URL (optional)', url: true),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field(_start, 'Start time')),
          const SizedBox(width: 12),
          Expanded(child: _field(_end, 'End time (optional)')),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Use seconds, mm:ss or hh:mm:ss. Pasted URL settings fill these fields.',
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      _button(
        _advanced ? 'Fewer playback options' : 'More playback options',
        () => setState(() => _advanced = !_advanced),
      ),
      if (_advanced) ...[
        _flag('Autoplay', _autoplay, (v) => _autoplay = v),
        _flag('Start muted', _muted, (v) => _muted = v),
        _flag('Loop video', _loop, (v) => _loop = v),
        _flag('Show captions', _captions, (v) => _captions = v),
        _field(_captionsLanguage, 'Caption language (e.g. en)'),
        const SizedBox(height: 12),
        _field(_playerLanguage, 'Player language (e.g. en)'),
      ],
    ],
  );

  Widget _button(String label, VoidCallback onPress) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: widget.enabled ? onPress : null,
      child: Text(label),
    ),
  );

  @override
  void dispose() {
    for (final c in [_url, _start, _end, _captionsLanguage, _playerLanguage]) {
      c.dispose();
    }
    super.dispose();
  }
}
