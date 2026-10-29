import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../repository/gamebase/gamebase_repository.dart';
import '../../../widgets/youtube_video_fields.dart';
import '../../../widgets/app_snack.dart';

/// Standalone author submissions use the same settings as collection videos.
class GameVideoSubmissionScreen extends ConsumerStatefulWidget {
  const GameVideoSubmissionScreen({
    super.key,
    required this.gameId,
    required this.pgn,
  });
  final String gameId, pgn;
  @override
  ConsumerState<GameVideoSubmissionScreen> createState() =>
      _GameVideoSubmissionScreenState();
}

class _GameVideoSubmissionScreenState
    extends ConsumerState<GameVideoSubmissionScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _language = TextEditingController();
  String _url = '';
  bool _busy = false;
  String? _error, _editing;
  List<Map<String, dynamic>> _submissions = const [];
  @override
  void initState() {
    super.initState();
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    _name.text = (metadata?['full_name'] ?? metadata?['name'] ?? '').toString();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(gamebaseRepositoryProvider)
          .getOwnGameAnalysisVideos(widget.gameId);
      if (mounted) setState(() => _submissions = items);
    } catch (_) {
      /* A failed history read never prevents a submission. */
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_url.trim().isEmpty) {
      setState(() => _error = 'Attach a YouTube video before submitting.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(gamebaseRepositoryProvider)
          .submitGameAnalysisVideo(
            gameId: widget.gameId,
            pgn: widget.pgn,
            url: _url,
            authorName: _name.text.trim(),
            language: _language.text.trim(),
            submissionId: _editing,
          );
      if (!mounted) return;
      setState(() => _editing = null);
      showAppSnack(
        context,
        'Video submitted for review',
        tone: AppSnackTone.success,
      );
      await _load();
    } catch (_) {
      if (mounted)
        {
        setState(
          () => _error =
              'Could not submit the video. Your edits are kept. Please try again.',
        );
        }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Video analysis')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Attach an analysis video to this game. It becomes public after a ChessEver superadmin approves it.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Author name'),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter your author name.'
                  : null,
            ),
            const SizedBox(height: 16),
            YoutubeVideoFields(
              key: ValueKey(_editing),
              value: _url,
              enabled: !_busy,
              onChanged: (value) => _url = value,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _language,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Spoken language (optional)',
                hintText: 'e.g. en or tr',
              ),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      RegExp(
                        r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$',
                      ).hasMatch(value.trim())
                  ? null
                  : 'Use a language code such as en or pt-BR.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Submitting…' : 'Submit for review'),
            ),
            if (_submissions.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Your submissions',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final item in _submissions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['authorName'] as String? ?? 'Video analysis',
                  ),
                  subtitle: Text(
                    '${item['status']}${item['note'] == null ? '' : ' · ${item['note']}'}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _editing = item['id'] as String;
                            _url = item['url'] as String;
                            _name.text = item['authorName'] as String;
                            _language.text = item['language'] as String? ?? '';
                          }),
                    child: const Text('Edit'),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    _name.dispose();
    _language.dispose();
    super.dispose();
  }
}
