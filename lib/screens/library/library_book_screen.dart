import 'package:chessever2/repository/library/library_book_publication.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> openLibraryBookEditor(
  BuildContext context,
  LibraryFolder folder,
) async {
  if (!libraryFolderCanPublish(folder)) return;
  if (!await requireFullAuthGuard(context) || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LibraryBookScreen(folder: folder)),
  );
}

/// Publication is explicit. Saving details alone preserves the current
/// visibility, and a failure leaves every entered field in place.
class LibraryBookScreen extends ConsumerStatefulWidget {
  const LibraryBookScreen({super.key, required this.folder});
  final LibraryFolder folder;
  @override
  ConsumerState<LibraryBookScreen> createState() => _LibraryBookScreenState();
}

class _LibraryBookScreenState extends ConsumerState<LibraryBookScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final name in [
      'title',
      'subtitle',
      'author',
      'about',
      'foreword',
      'publisher',
      'year',
      'cover',
    ])
      name: TextEditingController(),
  };
  LibraryBookPublication? _publication;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  bool _refreshGames = false;
  String _busyLabel = 'Saving book details…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _accept(LibraryBookPublication publication) {
    final m = publication.metadata;
    final values = {
      'title': m.title,
      'subtitle': m.subtitle,
      'author': m.author,
      'about': m.about,
      'foreword': m.foreword,
      'publisher': m.publisher,
      'year': m.publishedYear?.toString() ?? '',
      'cover': m.coverUrl,
    };
    for (final entry in values.entries) {
      _fields[entry.key]!.text = entry.value;
    }
    setState(() {
      _publication = publication;
      _dirty = false;
      _refreshGames = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final publication = await ref
          .read(libraryBookPublisherProvider)
          .load(widget.folder);
      if (mounted) _accept(publication);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => error is LibraryBookPublicationException
      ? error.message
      : 'Could not load book details. Please try again.';

  LibraryBookMetadata get _metadata => LibraryBookMetadata(
    title: _fields['title']!.text,
    subtitle: _fields['subtitle']!.text,
    author: _fields['author']!.text,
    about: _fields['about']!.text,
    foreword: _fields['foreword']!.text,
    publisher: _fields['publisher']!.text,
    publishedYear: int.tryParse(_fields['year']!.text.trim()),
    coverUrl: _fields['cover']!.text,
  );

  Future<void> _save({bool publish = false}) async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) {
      setState(
        () => _error = 'Check the highlighted book details before saving.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _busyLabel = publish || _refreshGames
          ? 'Saving book and indexing games…'
          : 'Saving book details…';
    });
    try {
      final saved = await ref
          .read(libraryBookPublisherProvider)
          .save(
            widget.folder,
            _metadata,
            publish: publish,
            // Explicit publishing includes the current folder, including when
            // restoring a previously withdrawn edition. Metadata saves do not.
            refreshGames: publish || _refreshGames,
          );
      if (!mounted) return;
      _accept(saved);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionsRepositoryProvider);
      ref.invalidate(collectionOpeningsProvider);
      ref.invalidate(collectionBooksForOpeningProvider);
      showAppSnack(
        context,
        saved.isPublished
            ? (publish ? 'Book published in Collections' : 'Book updated')
            : 'Book details saved privately',
        tone: AppSnackTone.success,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpublish() async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title: 'Unpublish book?',
      message:
          'Remove this book from Collections. Your private folder and saved book details will remain.',
      confirmText: 'Unpublish',
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _busyLabel = 'Unpublishing book…';
    });
    try {
      final saved = await ref
          .read(libraryBookPublisherProvider)
          .unpublish(widget.folder);
      if (!mounted) return;
      // Do not discard unsaved metadata while changing visibility.
      setState(() => _publication = saved);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionsRepositoryProvider);
      ref.invalidate(collectionOpeningsProvider);
      ref.invalidate(collectionBooksForOpeningProvider);
      showAppSnack(context, 'Book unpublished', tone: AppSnackTone.success);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showSmoothConfirmDialog(
        context: context,
        title: 'Discard book edits?',
        message: 'Your last saved details will remain.',
        confirmText: 'Discard',
      );
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Widget _field(
    String name,
    String label, {
    int lines = 1,
    int limit = 300,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: _fields[name],
      enabled: !_busy,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      maxLength: limit,
      keyboardType: name == 'year'
          ? TextInputType.number
          : name == 'cover'
          ? TextInputType.url
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      textCapitalization: name == 'cover' || name == 'year'
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      style: TextStyle(color: context.colors.textPrimary),
      onChanged: (_) {
        if (!_dirty) setState(() => _dirty = true);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: lines > 1,
        counterText: '',
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (raw) {
        final value = raw?.trim() ?? '';
        if (name == 'title' && value.isEmpty) return 'Enter a book title';
        if (name == 'year' && value.isNotEmpty) {
          final year = int.tryParse(value);
          if (year == null || year < 0 || year > 9999) {
            return 'Enter a valid publication year';
          }
        }
        if (name == 'cover' && value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              uri.scheme != 'https' ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            return 'Use an HTTPS image URL';
          }
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final published = _publication?.isPublished ?? false;
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          foregroundColor: context.colors.textPrimary,
          title: const Text('Book details'),
          leading: IconButton(
            onPressed: _busy ? null : _close,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _publication == null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error ?? 'Could not load book details',
                            style: TextStyle(color: context.colors.textPrimary),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : Form(
                      key: _form,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              published
                                  ? 'Published in Collections'
                                  : 'Private draft',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              published
                                  ? '${_publication!.gameCount} public games. Your source folder stays private.'
                                  : 'Publishing makes a public book from this folder, including its games, variations and annotations. Saving details keeps it private.',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _field('title', 'Title', limit: 300),
                            _field('author', 'Author', limit: 300),
                            _field('subtitle', 'Subtitle', limit: 300),
                            _field(
                              'about',
                              'Description',
                              lines: 4,
                              limit: 20000,
                            ),
                            _field(
                              'foreword',
                              'Foreword',
                              lines: 3,
                              limit: 50000,
                            ),
                            _field('publisher', 'Publisher', limit: 200),
                            _field('year', 'Publication year', limit: 4),
                            _field(
                              'cover',
                              'Cover image URL',
                              limit: 2000,
                              hint: 'https://…',
                            ),
                            if (published)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Update public games from this folder',
                                ),
                                subtitle: const Text(
                                  'Replaces the published snapshot with your current games and annotations.',
                                ),
                                value: _refreshGames,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                        _refreshGames = value ?? false;
                                        _dirty = true;
                                      }),
                              ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            if (_busy)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  children: [
                                    const LinearProgressIndicator(),
                                    const SizedBox(height: 8),
                                    Text(
                                      _busyLabel,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: context.colors.textPrimary,
                                foregroundColor: context.colors.background,
                                minimumSize: const Size.fromHeight(48),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _save(publish: !published),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  published ? 'Save changes' : 'Publish book',
                                ),
                              ),
                            ),
                            if (!published)
                              TextButton(
                                onPressed: _busy ? null : _save,
                                child: const Text('Save private draft'),
                              ),
                            if (published)
                              TextButton(
                                onPressed: _busy ? null : _unpublish,
                                child: const Text('Unpublish book'),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
