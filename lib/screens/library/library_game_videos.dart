import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../repository/library/library_repository.dart';
import '../../widgets/youtube_video_fields.dart';

/// Edits publication metadata only; a private source game is never rewritten.
class LibraryGameVideos extends ConsumerStatefulWidget {
  const LibraryGameVideos({
    super.key,
    required this.folderId,
    required this.value,
    required this.onChanged,
    this.languages = const {},
    required this.onLanguagesChanged,
    this.enabled = true,
  });
  final String folderId;
  final Map<String, String> value;
  final Map<String, String> languages;
  final ValueChanged<Map<String, String>> onLanguagesChanged;
  final ValueChanged<Map<String, String>> onChanged;
  final bool enabled;
  @override
  ConsumerState<LibraryGameVideos> createState() => _LibraryGameVideosState();
}

class _LibraryGameVideosState extends ConsumerState<LibraryGameVideos> {
  Future<List<({String id, String title})>>? _games;
  String? _editing;
  final _opened = <String>{};
  int _limit = 20;
  void _load() => setState(
    () => _games = ref
        .read(libraryRepositoryProvider)
        .getPublicationGameLabels(widget.folderId),
  );
  Widget _button(String label, VoidCallback onPress) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: widget.enabled ? onPress : null,
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _button('Game videos (optional)', _load),
      if (_games != null)
        FutureBuilder<List<({String id, String title})>>(
          future: _games,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Could not load the games. Your saved links are kept.',
                  ),
                  _button('Retry', _load),
                ],
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final games = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (games.isEmpty)
                  const Text('Add a game to this folder to attach a video.'),
                for (final game in games.take(_limit))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _button(
                          '${game.title}${widget.value.containsKey(game.id) ? ' · Video attached' : ''}',
                          () => setState(() {
                            _opened.add(game.id);
                            _editing = _editing == game.id ? null : game.id;
                          }),
                        ),
                        // Preserve fields while another game is edited, including invalid drafts.
                        if (_opened.contains(game.id))
                          Offstage(
                            offstage: _editing != game.id,
                            child: Column(
                              children: [
                                TextFormField(
                                  key: ValueKey('language-${game.id}'),
                                  initialValue: widget.languages[game.id] ?? '',
                                  enabled: widget.enabled,
                                  decoration: const InputDecoration(
                                    labelText: 'Spoken language (optional)',
                                  ),
                                  validator: (v) =>
                                      v == null ||
                                          v.isEmpty ||
                                          RegExp(
                                            r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$',
                                          ).hasMatch(v.trim())
                                      ? null
                                      : 'Use a language code such as en.',
                                  onChanged: (v) {
                                    final next = Map<String, String>.of(
                                      widget.languages,
                                    );
                                    if (v.trim().isEmpty) {
                                      next.remove(game.id);
                                    } else {
                                      next[game.id] = v.trim();
                                    }
                                    widget.onLanguagesChanged(next);
                                  },
                                ),
                                YoutubeVideoFields(
                                  key: ValueKey(game.id),
                                  value: widget.value[game.id] ?? '',
                                  enabled: widget.enabled,
                                  onChanged: (url) {
                                    final next = Map<String, String>.of(
                                      widget.value,
                                    );
                                    if (url.isEmpty) {
                                      next.remove(game.id);
                                    } else {
                                      next[game.id] = url;
                                    }
                                    widget.onChanged(next);
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (games.length > _limit)
                  _button(
                    'Show more games',
                    () => setState(() => _limit += 20),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 16),
    ],
  );
}
