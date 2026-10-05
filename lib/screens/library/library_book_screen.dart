import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/library/library_book_publication.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/library/cover_cropper.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionBookPlate;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps typed text tidy as it is entered: no leading space and no runs of
/// spaces. Single-line fields also refuse line breaks; multi-line ones allow
/// at most one blank line between paragraphs.
class _TidySpacesFormatter extends TextInputFormatter {
  const _TidySpacesFormatter({this.multiline = false});
  final bool multiline;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    text = multiline
        ? text.replaceAll(RegExp(r'\n{3,}'), '\n\n')
        : text.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    text = text
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceFirst(RegExp(r'^\s+'), '');
    if (text == newValue.text) return newValue;
    final removed = newValue.text.length - text.length;
    final offset = (newValue.selection.baseOffset - removed).clamp(
      0,
      text.length,
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

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

/// The fields this screen edits, in the order they read on the collection
/// page. Foreword and publisher are not edited here: the publisher is always
/// ChessEver's own editor, and a foreword belongs to a printed book, not to
/// a folder of games. Whatever the server already holds for them is kept.
enum _Field { title, subtitle, author, year, about, authorAbout }

/// Which preview the field is drawn in: the list row or the collection page.
const _listFields = {_Field.title, _Field.author};

/// The signed-in account's profile photo: the author picture of a collection
/// credited to "Me". Overridden in tests.
final libraryAuthorProfilePhotoProvider = Provider<String?>(
  (ref) => ref.watch(profileAvatarUrlProvider),
);

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
  final _fields = {for (final f in _Field.values) f: TextEditingController()};
  final _focus = {for (final f in _Field.values) f: FocusNode()};
  LibraryBookPublication? _publication;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  bool _refreshGames = false;
  String _busyLabel = 'Saving collection details…';
  String? _error;

  /// 0: as it reads in the Collections list, 1: as its page opens.
  int _previewTab = 0;
  _Field? _focused;

  /// The cover lives on the server: it is uploaded as soon as it is picked,
  /// and the saved link is carried through every details save.
  String _coverUrl = '';
  Uint8List? _coverPreview;
  bool _coverBusy = false;

  /// Who the author credit names. "Me" is pictured by the profile photo;
  /// someone else by this collection's own author photo, uploaded on pick.
  LibraryAuthorCredit _credit = LibraryAuthorCredit.self;

  /// Whether the server knows author credits: an older one refuses the key,
  /// so "Me" is only sent once it has answered with one.
  bool _creditKnown = false;
  String _authorPhotoUrl = '';
  Uint8List? _authorPhotoPreview;
  bool _authorPhotoBusy = false;

  /// The remembered own name was filled in, not typed: crediting someone
  /// else clears it instead of crediting them under the publisher's name.
  bool _authorPrefilled = false;

  /// Existing ChessEver authors for what is typed, so one person keeps one
  /// spelling across collections. [_suggestionsFor] is the name they answer.
  List<LibraryAuthorSuggestion> _suggestions = const [];
  String _suggestionsFor = '';
  int _suggestSeq = 0;
  Timer? _suggestTimer;

  bool get _anyBusy => _busy || _coverBusy || _authorPhotoBusy;
  bool get _creditsOther => _credit == LibraryAuthorCredit.other;

  @override
  void initState() {
    super.initState();
    for (final entry in _focus.entries) {
      entry.value.addListener(() => _onFocus(entry.key, entry.value));
    }
    _load();
  }

  @override
  void dispose() {
    _stashTimer?.cancel();
    _suggestTimer?.cancel();
    // Leaving mid-edit (back gesture, app route reset) still keeps the work.
    if (_dirty) _stashDraft();
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Follow the field being edited: the preview turns to where that field
  /// shows, and its spot there lights up.
  void _onFocus(_Field field, FocusNode node) {
    if (!mounted) return;
    if (node.hasFocus) {
      setState(() {
        _focused = field;
        _previewTab = _listFields.contains(field) ? 0 : 1;
      });
    } else if (_focused == field) {
      setState(() => _focused = null);
    }
  }

  void _accept(LibraryBookPublication publication) {
    final m = publication.metadata;
    final values = {
      _Field.title: m.title,
      _Field.subtitle: m.subtitle,
      _Field.author: m.author,
      _Field.about: m.about,
      _Field.authorAbout: m.authorAbout ?? '',
      _Field.year: m.publishedYear?.toString() ?? '',
    };
    for (final entry in values.entries) {
      _fields[entry.key]!.text = entry.value;
    }
    final credit = m.authorCredit ?? LibraryAuthorCredit.self;
    _authorPrefilled = false;
    if (m.author.trim().isEmpty && credit == LibraryAuthorCredit.self) {
      _prefillRemembered();
    }
    setState(() {
      _publication = publication;
      _coverUrl = m.coverUrl;
      _credit = credit;
      _creditKnown = m.authorCredit != null;
      _authorPhotoUrl = m.authorPhotoUrl;
      _authorPhotoPreview = null;
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
    // Asked once the form is on screen, so the user sees what they resume.
    if (mounted && _publication != null && _error == null) await _offerDraft();
  }

  String _message(Object error) => error is LibraryBookPublicationException
      ? error.message
      : 'Could not load collection details. Please try again.';

  String _text(_Field field) => _fields[field]!.text;

  /// Unsubmitted edits live on this device, per folder, until the server
  /// accepts a save. Coming back offers to pick up where the user left off.
  String get _draftKey => 'library_book.draft.${widget.folder.id}';
  Timer? _stashTimer;

  void _scheduleStash() {
    _stashTimer?.cancel();
    _stashTimer = Timer(const Duration(milliseconds: 500), _stashDraft);
  }

  Future<void> _stashDraft() async {
    // Read synchronously: this also runs from dispose().
    final values = {
      for (final f in _Field.values) f.name: _text(f),
      'authorCredit': _credit.name,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(values));
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    _stashTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _offerDraft() async {
    Map<String, dynamic>? draft;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw != null) draft = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      draft = null;
    }
    if (draft == null || !mounted) return;
    final values = {
      for (final f in _Field.values)
        if (draft[f.name] is String) f: draft[f.name] as String,
    };
    final draftCredit = draft['authorCredit'] is String
        ? LibraryAuthorCredit.parse(draft['authorCredit'])
        : _credit;
    final differs =
        draftCredit != _credit ||
        values.entries.any((e) => e.value.trim() != _text(e.key).trim());
    if (!differs) {
      await _clearDraft();
      return;
    }
    final resume = await showSmoothConfirmDialog(
      context: context,
      title: 'Continue where you left off?',
      message:
          'You have unsubmitted changes to this collection from your last visit.',
      confirmText: 'Continue',
      cancelText: 'Start over',
    );
    if (!mounted) return;
    if (resume == true) {
      setState(() {
        for (final e in values.entries) {
          _fields[e.key]!.text = e.value;
        }
        _credit = draftCredit;
        _authorPrefilled = false;
        _dirty = true;
      });
    } else if (resume == false) {
      await _clearDraft();
    }
    // Dismissed without choosing: keep the draft for next time.
  }

  /// The author is usually the same person on every collection, so the last
  /// one saved pre-fills a fresh collection. Stored on this device only.
  static const _lastAuthorKey = 'library_book.last_author';

  Future<void> _prefillRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final author = prefs.getString(_lastAuthorKey)?.trim() ?? '';
      final field = _fields[_Field.author]!;
      if (!mounted ||
          author.isEmpty ||
          field.text.trim().isNotEmpty ||
          _creditsOther) {
        return;
      }
      setState(() {
        field.text = author;
        _authorPrefilled = true;
      });
    } catch (_) {
      // A missing preference only means no pre-fill.
    }
  }

  /// Only the account's own name is remembered: crediting someone else on
  /// one collection must not pre-fill their name on the next.
  Future<void> _remember(LibraryBookMetadata metadata) async {
    final author = metadata.author.trim();
    if (author.isEmpty ||
        (metadata.authorCredit ?? _credit) != LibraryAuthorCredit.self) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAuthorKey, author);
    } catch (_) {}
  }

  LibraryBookMetadata get _metadata {
    final saved = _publication?.metadata;
    return LibraryBookMetadata(
      title: _text(_Field.title).trim(),
      subtitle: _text(_Field.subtitle).trim(),
      author: _text(_Field.author).trim(),
      about: _text(_Field.about).trim(),
      // An older server refuses the key, so an empty one it never showed
      // is left out.
      authorAbout:
          _publication?.metadata.authorAbout != null ||
              _text(_Field.authorAbout).trim().isNotEmpty
          ? _text(_Field.authorAbout).trim()
          : null,
      // Not editable here; carried through so a save never erases them.
      foreword: saved?.foreword ?? '',
      publisher: saved?.publisher ?? '',
      publishedYear: int.tryParse(_text(_Field.year).trim()),
      // Set by the cover upload, never typed; carried through on save.
      coverUrl: _coverUrl,
      authorCredit: _creditsOther
          ? LibraryAuthorCredit.other
          : _creditKnown
          ? LibraryAuthorCredit.self
          : null,
    );
  }

  bool _validateForReview = false;

  Future<void> _save({bool publish = false}) async {
    if (_anyBusy) return;
    _validateForReview = publish;
    if (!(_form.currentState?.validate() ?? false)) {
      setState(
        () =>
            _error = 'Check the highlighted collection details before saving.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _busyLabel = publish || _refreshGames
          ? 'Saving collection and indexing games…'
          : 'Saving collection details…';
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
      unawaited(_clearDraft());
      _remember(saved.metadata);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionsRepositoryProvider);
      ref.invalidate(collectionOpeningsProvider);
      ref.invalidate(collectionBooksForOpeningProvider);
      showAppSnack(
        context,
        saved.isPublished
            ? 'Collection updated'
            : publish
            ? 'Submitted for ChessEver approval'
            : 'Collection details saved privately',
        tone: AppSnackTone.success,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pick a photo, prepare the 2:3 cover and upload it straight away. A
  /// cover belongs to a saved collection, so a never-saved one is first
  /// saved as a private draft with what is typed.
  Future<void> _pickCover() async {
    if (_anyBusy) return;
    final Uint8List? image;
    try {
      image = await ref.read(collectionCoverPickerProvider)(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    }
    if (image == null || !mounted) return;
    final wasPublished = _publication?.isPublished ?? false;
    setState(() {
      _coverBusy = true;
      _coverPreview = image;
      _error = null;
    });
    try {
      final publisher = ref.read(libraryBookPublisherProvider);
      if (_publication?.bookId == null) {
        _validateForReview = false;
        if (!(_form.currentState?.validate() ?? false)) {
          throw const LibraryBookPublicationException(
            'Add a title first. The cover is saved with the collection.',
          );
        }
        final saved = await publisher.save(widget.folder, _metadata);
        if (!mounted) return;
        _accept(saved);
        unawaited(_clearDraft());
        _remember(saved.metadata);
      }
      final result = await publisher.uploadCover(widget.folder, image);
      if (!mounted) return;
      setState(() {
        _publication = result;
        _coverUrl = result.metadata.coverUrl;
      });
      _invalidateCollections();
      showAppSnack(
        context,
        wasPublished
            ? 'Cover saved. ChessEver will review the change.'
            : 'Cover saved',
        tone: AppSnackTone.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _coverPreview = null;
          _error = error is LibraryBookPublicationException
              ? error.message
              : 'Could not save the cover. Retry when connected.';
        });
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _removeCover() async {
    if (_anyBusy) return;
    setState(() {
      _coverBusy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(libraryBookPublisherProvider)
          .removeCover(widget.folder);
      if (!mounted) return;
      setState(() {
        _publication = result;
        _coverUrl = result.metadata.coverUrl;
        _coverPreview = null;
      });
      _invalidateCollections();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LibraryBookPublicationException
              ? error.message
              : 'Could not remove the cover. Retry when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  /// "Me" or "Someone else". Crediting someone else clears a name that was
  /// only pre-filled with the publisher's own; going back to "Me" fills it in.
  void _setCredit(LibraryAuthorCredit next) {
    if (next == _credit || _anyBusy) return;
    final author = _fields[_Field.author]!;
    setState(() {
      _credit = next;
      _dirty = true;
      if (next == LibraryAuthorCredit.other && _authorPrefilled) {
        author.clear();
        _authorPrefilled = false;
      }
      // The description is about whoever was credited: one that was only
      // loaded does not follow the credit to another person, and comes back
      // with the credit it was loaded for.
      final about = _fields[_Field.authorAbout]!;
      final loaded = _publication?.metadata.authorAbout?.trim() ?? '';
      final loadedFor =
          _publication?.metadata.authorCredit ?? LibraryAuthorCredit.self;
      if (loaded.isNotEmpty) {
        if (next != loadedFor && about.text.trim() == loaded) {
          about.clear();
        } else if (next == loadedFor && about.text.trim().isEmpty) {
          about.text = loaded;
        }
      }
      _suggestions = const [];
      _suggestionsFor = '';
    });
    if (next == LibraryAuthorCredit.self && author.text.trim().isEmpty) {
      _prefillRemembered();
    }
    _scheduleSuggestions();
    _scheduleStash();
  }

  String get _authorTerm =>
      _text(_Field.author).trim().replaceAll(RegExp(r'\s+'), ' ');

  void _scheduleSuggestions() {
    _suggestTimer?.cancel();
    final term = _authorTerm;
    if (!_creditsOther || term.length < 2) {
      _suggestSeq++;
      if (_suggestions.isNotEmpty || _suggestionsFor.isNotEmpty) {
        setState(() {
          _suggestions = const [];
          _suggestionsFor = '';
        });
      }
      return;
    }
    _suggestTimer = Timer(
      const Duration(milliseconds: 300),
      () => _fetchSuggestions(term),
    );
  }

  Future<void> _fetchSuggestions(String term) async {
    final seq = ++_suggestSeq;
    final items = await ref
        .read(libraryBookPublisherProvider)
        .suggestAuthors(term);
    // A later request, a changed name or a changed credit wins.
    if (!mounted || seq != _suggestSeq || !_creditsOther) return;
    if (_authorTerm != term) return;
    setState(() {
      _suggestions = items;
      _suggestionsFor = term;
    });
  }

  /// The existing author whose name is exactly the one typed, if any.
  LibraryAuthorSuggestion? get _matchedAuthor {
    final typed = _authorTerm.toLowerCase();
    if (typed.isEmpty || _suggestionsFor.toLowerCase() != typed) return null;
    for (final s in _suggestions) {
      if (s.name.toLowerCase() == typed) return s;
    }
    return null;
  }

  void _useSuggestion(LibraryAuthorSuggestion suggestion) {
    final field = _fields[_Field.author]!;
    setState(() {
      field.value = TextEditingValue(
        text: suggestion.name,
        selection: TextSelection.collapsed(offset: suggestion.name.length),
      );
      _authorPrefilled = false;
      _suggestions = [suggestion];
      _suggestionsFor = suggestion.name;
      _dirty = true;
    });
    _scheduleStash();
  }

  /// Pick and frame a square photo of the credited author and upload it at
  /// once. Like the cover, it needs a saved collection, so a never-saved one
  /// is first saved as a private draft (credited to someone else).
  Future<void> _pickAuthorPhoto() async {
    if (_anyBusy) return;
    final Uint8List? image;
    try {
      image = await ref.read(authorPhotoPickerProvider)(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    }
    if (image == null || !mounted) return;
    final wasPublished = _publication?.isPublished ?? false;
    setState(() {
      _authorPhotoBusy = true;
      _authorPhotoPreview = image;
      _credit = LibraryAuthorCredit.other;
      _error = null;
    });
    try {
      final publisher = ref.read(libraryBookPublisherProvider);
      if (_publication?.bookId == null) {
        _validateForReview = false;
        if (!(_form.currentState?.validate() ?? false)) {
          throw const LibraryBookPublicationException(
            'Add a title first. The author photo is saved with the collection.',
          );
        }
        final saved = await publisher.save(widget.folder, _metadata);
        if (!mounted) return;
        _accept(saved);
        unawaited(_clearDraft());
        setState(() {
          _credit = LibraryAuthorCredit.other;
          _authorPhotoPreview = image;
        });
      }
      final result = await publisher.uploadAuthorPhoto(widget.folder, image);
      if (!mounted) return;
      setState(() {
        _publication = result;
        _authorPhotoUrl = result.metadata.authorPhotoUrl;
        _credit = LibraryAuthorCredit.other;
        _creditKnown = _creditKnown || result.metadata.authorCredit != null;
      });
      _invalidateCollections();
      showAppSnack(
        context,
        wasPublished
            ? 'Author photo saved. ChessEver will review the change.'
            : 'Author photo saved',
        tone: AppSnackTone.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _authorPhotoPreview = null;
          _error = error is LibraryBookPublicationException
              ? error.message
              : 'Could not save the author photo. Retry when connected.';
        });
      }
    } finally {
      if (mounted) setState(() => _authorPhotoBusy = false);
    }
  }

  Future<void> _removeAuthorPhoto() async {
    if (_anyBusy) return;
    setState(() {
      _authorPhotoBusy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(libraryBookPublisherProvider)
          .removeAuthorPhoto(widget.folder);
      if (!mounted) return;
      setState(() {
        _publication = result;
        _authorPhotoUrl = result.metadata.authorPhotoUrl;
        _authorPhotoPreview = null;
      });
      _invalidateCollections();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LibraryBookPublicationException
              ? error.message
              : 'Could not remove the author photo. Retry when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _authorPhotoBusy = false);
    }
  }

  void _invalidateCollections() {
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionsRepositoryProvider);
    ref.invalidate(collectionOpeningsProvider);
    ref.invalidate(collectionBooksForOpeningProvider);
  }

  Future<void> _unpublish() async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title: 'Unpublish collection?',
      message:
          'Remove this collection from Collections. Your private folder and saved collection details will remain.',
      confirmText: 'Unpublish',
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _busyLabel = 'Unpublishing collection…';
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
      showAppSnack(
        context,
        'Collection unpublished',
        tone: AppSnackTone.success,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    // Nothing to discard: unsaved edits are kept on the device and offered
    // back on the next visit.
    if (_dirty) await _stashDraft();
    if (!mounted) return;
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String? _validate(_Field field, String? raw) {
    final value = raw?.trim() ?? '';
    switch (field) {
      case _Field.title:
        if (value.isEmpty) return 'Enter a collection title';
        return value.length < 3 ? 'Use at least 3 characters' : null;
      case _Field.author:
        if (value.isEmpty) {
          return _validateForReview ? 'Credit the author by name' : null;
        }
        return RegExp(r'\p{L}{2}', unicode: true).hasMatch(value)
            ? null
            : 'Enter the author’s name';
      case _Field.about:
        return _validateForReview && value.isEmpty
            ? 'Describe this collection'
            : null;
      case _Field.authorAbout:
        return null;
      case _Field.year:
        if (value.isEmpty) return null;
        final year = int.tryParse(value);
        return year == null || year < 1000 || year > DateTime.now().year + 1
            ? 'Enter a four-digit year'
            : null;
      case _Field.subtitle:
        return value.isNotEmpty &&
                value.toLowerCase() == _text(_Field.title).trim().toLowerCase()
            ? 'Say something the title doesn’t'
            : null;
    }
  }

  Widget _field(
    _Field field, {
    required String label,
    required String where,
    required String hint,
    bool optional = false,
    int lines = 1,
    int limit = 300,
    Widget? above,
    Widget? below,
  }) {
    final colors = context.colors;
    final radius = BorderRadius.circular(10.br);
    OutlineInputBorder outline(Color color) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (optional) ...[
                SizedBox(width: 6.sp),
                Text(
                  'Optional',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.textInk(0.45),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 2.sp),
          Text(
            where,
            style: AppTypography.textXsRegular.copyWith(
              color: context.textInk(0.55),
              height: 16 / 12,
            ),
          ),
          SizedBox(height: 8.sp),
          if (above != null) ...[above, SizedBox(height: 10.sp)],
          TextFormField(
            controller: _fields[field],
            focusNode: _focus[field],
            enabled: !_busy,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 4,
            maxLength: limit,
            keyboardType: switch (field) {
              _Field.year => TextInputType.number,
              _ when lines > 1 => TextInputType.multiline,
              _ => TextInputType.text,
            },
            inputFormatters: switch (field) {
              _Field.year => [FilteringTextInputFormatter.digitsOnly],
              _Field.author => [
                // Names only: letters (any script), spaces and . ' - , &.
                FilteringTextInputFormatter.allow(
                  RegExp(r"[\p{L}\p{M} .'’\-,&]", unicode: true),
                ),
                const _TidySpacesFormatter(),
              ],
              _Field.about || _Field.authorAbout => [
                const _TidySpacesFormatter(multiline: true),
              ],
              _ => [const _TidySpacesFormatter()],
            },
            // Author is a proper name: every word starts upper-case, so
            // "Jason Statham" is not turned into "Jason statham".
            textCapitalization: switch (field) {
              _Field.year => TextCapitalization.none,
              _Field.title ||
              _Field.subtitle ||
              _Field.author => TextCapitalization.words,
              _ => TextCapitalization.sentences,
            },
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textPrimary,
              fontSize: 15.f,
              height: 22 / 15,
            ),
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
              if (field == _Field.author) {
                _authorPrefilled = false;
                _scheduleSuggestions();
              }
              _scheduleStash();
            },
            decoration: InputDecoration(
              hintText: hint,
              hintMaxLines: lines,
              hintStyle: AppTypography.textSmRegular.copyWith(
                color: context.textInk(0.35),
                fontSize: 15.f,
                height: 22 / 15,
              ),
              // A counter only where the limit is close enough to matter.
              counterText: limit >= 100 && limit <= 2000 ? null : '',
              counterStyle: AppTypography.textXsRegular.copyWith(
                color: context.textInk(0.45),
              ),
              isDense: true,
              filled: true,
              fillColor: colors.textPrimary.withValues(alpha: 0.03),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.sp,
                vertical: 13.sp,
              ),
              border: outline(colors.textPrimary.withValues(alpha: 0.06)),
              enabledBorder: outline(
                colors.textPrimary.withValues(alpha: 0.06),
              ),
              disabledBorder: outline(
                colors.textPrimary.withValues(alpha: 0.04),
              ),
              focusedBorder: outline(colors.textPrimary.withValues(alpha: 0.3)),
              errorBorder: outline(colors.danger.withValues(alpha: 0.7)),
              focusedErrorBorder: outline(colors.danger),
              errorStyle: AppTypography.textXsRegular.copyWith(
                color: colors.danger,
              ),
            ),
            validator: (raw) => _validate(field, raw),
          ),
          ?below,
        ],
      ),
    );
  }

  Widget _status(bool published) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: 8.sp,
          height: 8.sp,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: published ? colors.success : context.textInk(0.35),
          ),
        ),
        SizedBox(width: 8.sp),
        Expanded(
          child: Text(
            published
                ? 'Published · ${_plural(_publication!.gameCount, 'game')} in Collections'
                : 'Private draft · only you can see it',
            style: AppTypography.textXsMedium.copyWith(
              color: context.textInk(0.7),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final published = _publication?.isPublished ?? false;
    final colors = context.colors;
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          foregroundColor: colors.textPrimary,
          title: Text(published ? 'Edit collection' : 'Publish collection'),
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
                            _error ?? 'Could not load collection details',
                            style: TextStyle(color: colors.textPrimary),
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
                        padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 32.sp),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _status(published),
                            SizedBox(height: 20.sp),
                            _sectionHeading('Preview'),
                            SizedBox(height: 10.sp),
                            SegmentedSwitcher(
                              options: const ['In the list', 'Collection page'],
                              currentSelection: _previewTab,
                              onSelectionChanged: (i) =>
                                  setState(() => _previewTab = i),
                            ),
                            SizedBox(height: 12.sp),
                            ListenableBuilder(
                              listenable: Listenable.merge(_fields.values),
                              builder: (context, _) => _BookPreview(
                                page: _previewTab == 1,
                                title: _text(_Field.title).trim(),
                                subtitle: _text(_Field.subtitle).trim(),
                                author: _text(_Field.author).trim(),
                                year: _text(_Field.year).trim(),
                                about: _text(_Field.about).trim(),
                                cover: _coverUri(_coverUrl),
                                coverBytes: _coverPreview,
                                coverLit: _coverBusy,
                                publisher: _publication!.metadata.publisher
                                    .trim(),
                                gameCount: _publication!.gameCount,
                                focused: _focused,
                              ),
                            ),
                            SizedBox(height: 28.sp),
                            _sectionHeading('Details'),
                            SizedBox(height: 4.sp),
                            Text(
                              'Everything is needed to submit unless marked Optional.',
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.textInk(0.55),
                              ),
                            ),
                            SizedBox(height: 16.sp),
                            _field(
                              _Field.title,
                              label: 'Title',
                              where:
                                  'The name readers see in the list and on top of the page.',
                              hint: 'e.g. Carlsen’s Best Endgames',
                              limit: 80,
                            ),
                            _field(
                              _Field.subtitle,
                              label: 'Subtitle',
                              optional: true,
                              where:
                                  'One short line under the title on the collection page. It adds detail the title leaves out.',
                              hint: 'e.g. 40 annotated wins, 2013–2023',
                              limit: 120,
                            ),
                            _field(
                              _Field.author,
                              label: 'Author',
                              where: _creditsOther
                                  ? 'The person who wrote or compiled it, credited as “by …” in the list and on the page. Pick a name below if they’re already on ChessEver, so their collections stay together.'
                                  : 'Credited as “by …” in the list and on the page.',
                              hint: 'e.g. Magnus Carlsen',
                              limit: 60,
                              above: _creditSwitch(),
                              below: _authorExtras(published),
                            ),
                            _field(
                              _Field.authorAbout,
                              label: 'About the author',
                              optional: true,
                              where: _creditsOther
                                  ? 'A few lines about them, on their author page and under “About the author” here. Leave it empty to keep what their other collections say.'
                                  : 'A few lines about you, on your author page and under “About the author” here.',
                              hint:
                                  'e.g. International Master and coach from Baku, writing about endgames since 2015.',
                              lines: 3,
                              limit: 4000,
                            ),
                            _field(
                              _Field.year,
                              label: 'Year',
                              optional: true,
                              where: 'Shown on the page under the author.',
                              hint: 'e.g. ${DateTime.now().year}',
                              limit: 4,
                            ),
                            _field(
                              _Field.about,
                              label: 'Description',
                              where:
                                  'Opens the page under “About this collection”.',
                              hint:
                                  'What’s inside, who it’s for, and what readers will take away.',
                              lines: 4,
                              limit: 1500,
                            ),
                            _coverPicker(published),
                            if (published)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Update collection games from this folder',
                                ),
                                subtitle: const Text(
                                  'Includes your current games and annotations in the review.',
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
                                padding: EdgeInsets.only(bottom: 16.sp),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: AppTypography.textSmRegular.copyWith(
                                      color: colors.danger,
                                    ),
                                  ),
                                ),
                              ),
                            if (_busy)
                              Padding(
                                padding: EdgeInsets.only(bottom: 16.sp),
                                child: Column(
                                  children: [
                                    const LinearProgressIndicator(),
                                    SizedBox(height: 8.sp),
                                    Text(
                                      _busyLabel,
                                      textAlign: TextAlign.center,
                                      style: AppTypography.textXsRegular
                                          .copyWith(
                                            color: context.textInk(0.6),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.textPrimary,
                                foregroundColor: colors.background,
                                minimumSize: const Size.fromHeight(48),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.br),
                                ),
                                textStyle: AppTypography.textSmMedium,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _save(publish: true),
                              child: Text(
                                published
                                    ? 'Submit changes'
                                    : 'Submit for approval',
                              ),
                            ),
                            SizedBox(height: 8.sp),
                            Text(
                              'ChessEver reviews every collection before it appears in Collections.',
                              textAlign: TextAlign.center,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.textInk(0.5),
                              ),
                            ),
                            SizedBox(height: 4.sp),
                            if (!published)
                              TextButton(
                                onPressed: _busy ? null : _save,
                                child: const Text('Save private draft'),
                              ),
                            if (published)
                              TextButton(
                                onPressed: _busy ? null : _unpublish,
                                child: const Text('Unpublish collection'),
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

  /// The cover: a 2:3 thumbnail with Choose / Replace and Remove. It is the
  /// collection's own image, not the profile photo shown for the author.
  Widget _coverPicker(bool published) {
    final colors = context.colors;
    final url = _coverUri(_coverUrl);
    final hasCover = _coverPreview != null || url != null;
    final enabled = !_busy && !_coverBusy;
    final thumb = _coverPreview != null
        ? Image.memory(_coverPreview!, fit: BoxFit.cover)
        : url != null
        ? CachedNetworkImage(
            imageUrl: url.toString(),
            fit: BoxFit.cover,
            placeholder: (_, __) => const CollectionBookPlate(),
            errorWidget: (_, __, ___) => const CollectionBookPlate(),
          )
        : const CollectionBookPlate();
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Cover',
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(width: 6.sp),
              Text(
                'Optional',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.textInk(0.45),
                ),
              ),
            ],
          ),
          SizedBox(height: 2.sp),
          Text(
            'Shown on the collection card and page. You frame it as a 2:3 portrait after choosing. Without one, the stacked boards are shown.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.textInk(0.55),
              height: 16 / 12,
            ),
          ),
          SizedBox(height: 10.sp),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                image: true,
                label: hasCover ? 'Collection cover' : 'No cover yet',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6.br),
                  child: SizedBox(
                    width: 64.w,
                    height: 96.w,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        thumb,
                        if (_coverBusy)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 20.sp,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16.sp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('book_cover_choose'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        minimumSize: const Size(0, 44),
                        side: BorderSide(
                          color: colors.textPrimary.withValues(alpha: 0.16),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.br),
                        ),
                        textStyle: AppTypography.textSmMedium,
                      ),
                      onPressed: enabled ? _pickCover : null,
                      child: Text(
                        _coverBusy
                            ? 'Saving cover…'
                            : hasCover
                            ? 'Replace photo'
                            : 'Choose from gallery',
                      ),
                    ),
                    if (hasCover && !_coverBusy)
                      TextButton(
                        key: const ValueKey('book_cover_remove'),
                        style: TextButton.styleFrom(
                          foregroundColor: context.textInk(0.6),
                          minimumSize: const Size(0, 44),
                          padding: EdgeInsets.symmetric(horizontal: 4.sp),
                          textStyle: AppTypography.textSmRegular,
                        ),
                        onPressed: enabled ? _removeCover : null,
                        child: const Text('Remove cover'),
                      ),
                    if (published)
                      Text(
                        'A new cover goes to ChessEver for review.',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.textInk(0.45),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Me" or "Someone else": who the collection is credited to.
  Widget _creditSwitch() => Semantics(
    label: 'Who is this collection credited to?',
    child: SegmentedSwitcher(
      key: const ValueKey('book_author_credit'),
      options: const ['Me', 'Someone else'],
      currentSelection: _creditsOther ? 1 : 0,
      onSelectionChanged: (i) => _setCredit(
        i == 1 ? LibraryAuthorCredit.other : LibraryAuthorCredit.self,
      ),
    ),
  );

  /// Under the name: for "Me", the profile photo it is pictured with; for
  /// someone else, existing ChessEver names to match and their own photo.
  Widget _authorExtras(bool published) {
    return ListenableBuilder(
      listenable: _fields[_Field.author]!,
      builder: (context, _) {
        final name = _text(_Field.author).trim();
        if (!_creditsOther) {
          final profile = ref.watch(libraryAuthorProfilePhotoProvider);
          return Padding(
            padding: EdgeInsets.only(top: 12.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _authorRow(
                  name: name,
                  photo: _AuthorAvatar(url: profile, size: 40.sp),
                  note: 'Your ChessEver profile photo is shown with your name.',
                ),
                if (_authorPhotoUrl.isNotEmpty) ...[
                  SizedBox(height: 8.sp),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'The saved author photo will be removed when you save.',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        final matched = _matchedAuthor;
        final showList =
            matched == null &&
            _suggestions.isNotEmpty &&
            _suggestionsFor.toLowerCase() == _authorTerm.toLowerCase();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showList) _suggestionList(),
            if (matched != null)
              Padding(
                padding: EdgeInsets.only(top: 8.sp),
                child: Text(
                  'Matches an existing ChessEver author.',
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.success,
                  ),
                ),
              ),
            SizedBox(height: 16.sp),
            _authorPhotoPicker(published, name, matched),
          ],
        );
      },
    );
  }

  Widget _suggestionList() {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.only(top: 8.sp),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(color: colors.textPrimary.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14.sp, 10.sp, 14.sp, 2.sp),
            child: Text(
              'Already on ChessEver',
              style: AppTypography.textXsRegular.copyWith(
                color: context.textInk(0.5),
              ),
            ),
          ),
          for (final s in _suggestions)
            Semantics(
              button: true,
              label:
                  'Use ${s.name}, ${_plural(s.bookCount, 'collection')} on ChessEver',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('book_author_suggestion_${s.name}'),
                onTap: _busy ? null : () => _useSuggestion(s),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.sp,
                      vertical: 6.sp,
                    ),
                    child: Row(
                      children: [
                        _AuthorAvatar(url: s.avatarUrl, size: 32.sp),
                        SizedBox(width: 12.sp),
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textSmMedium.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.sp),
                        Text(
                          _plural(s.bookCount, 'collection'),
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.textInk(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(height: 4.sp),
        ],
      ),
    );
  }

  /// A small row as the author appears with their name in Collections.
  Widget _authorRow({
    required String name,
    required Widget photo,
    required String note,
  }) => Row(
    children: [
      photo,
      SizedBox(width: 12.sp),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Author name' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: name.isEmpty
                    ? context.textInk(0.35)
                    : context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 2.sp),
            Text(
              note,
              style: AppTypography.textXsRegular.copyWith(
                color: context.textInk(0.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// The credited author's own photo: a circle with Choose / Replace and
  /// Remove. Not the profile photo and not the cover.
  Widget _authorPhotoPicker(
    bool published,
    String name,
    LibraryAuthorSuggestion? matched,
  ) {
    final colors = context.colors;
    final own = _authorPhotoPreview != null || _authorPhotoUrl.isNotEmpty;
    final borrowed = !own && matched?.avatarUrl != null;
    final enabled = !_anyBusy;
    final photo = _AuthorAvatar(
      bytes: _authorPhotoPreview,
      url: _authorPhotoPreview != null
          ? null
          : own
          ? _authorPhotoUrl
          : matched?.avatarUrl,
      size: 64.sp,
      busy: _authorPhotoBusy,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Author photo',
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
            SizedBox(width: 6.sp),
            Text(
              'Optional',
              style: AppTypography.textXsRegular.copyWith(
                color: context.textInk(0.45),
              ),
            ),
          ],
        ),
        SizedBox(height: 2.sp),
        Text(
          'A square photo of the author, shown with their name in Collections. Not your profile photo.',
          style: AppTypography.textXsRegular.copyWith(
            color: context.textInk(0.55),
            height: 16 / 12,
          ),
        ),
        SizedBox(height: 10.sp),
        Row(
          children: [
            Semantics(
              image: true,
              label: own
                  ? 'Author photo of ${name.isEmpty ? 'the author' : name}'
                  : 'No author photo yet',
              child: photo,
            ),
            SizedBox(width: 16.sp),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton(
                    key: const ValueKey('book_author_photo_choose'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      minimumSize: const Size(0, 44),
                      side: BorderSide(
                        color: colors.textPrimary.withValues(alpha: 0.16),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.br),
                      ),
                      textStyle: AppTypography.textSmMedium,
                    ),
                    onPressed: enabled ? _pickAuthorPhoto : null,
                    child: Text(
                      _authorPhotoBusy
                          ? 'Saving photo…'
                          : own
                          ? 'Replace photo'
                          : 'Choose from gallery',
                    ),
                  ),
                  if (own && !_authorPhotoBusy)
                    TextButton(
                      key: const ValueKey('book_author_photo_remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.textInk(0.6),
                        minimumSize: const Size(0, 44),
                        padding: EdgeInsets.symmetric(horizontal: 4.sp),
                        textStyle: AppTypography.textSmRegular,
                      ),
                      onPressed: enabled ? _removeAuthorPhoto : null,
                      child: const Text('Remove photo'),
                    ),
                  if (borrowed)
                    Text(
                      'Using the photo already on ChessEver for this author.',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.textInk(0.5),
                      ),
                    )
                  else if (published)
                    Text(
                      'A new photo goes to ChessEver for review.',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.textInk(0.45),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeading(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: AppTypography.textSmMedium.copyWith(
        color: context.colors.textPrimary,
        fontSize: 15.f,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// An HTTPS image link, or null when [raw] is not one.
Uri? _coverUri(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// An author picture as Collections shows it: a circle. Without a photo it
/// is a neutral silhouette, never initials.
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    this.url,
    this.bytes,
    required this.size,
    this.busy = false,
  });

  final String? url;
  final Uint8List? bytes;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final uri = url == null ? null : _coverUri(url!);
    final placeholder = ColoredBox(
      color: context.colors.textPrimary.withValues(alpha: 0.06),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.56,
        color: context.textInk(0.35),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes!, fit: BoxFit.cover)
            else if (uri != null)
              CachedNetworkImage(
                imageUrl: uri.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              )
            else
              placeholder,
            if (busy)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.4),
                child: Center(
                  child: SizedBox.square(
                    dimension: size * 0.32,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The collection as it will be drawn, built from what is typed now: the
/// list row is the Collections list's own row; the page is the top of the
/// collection's About page. An empty optional field leaves no trace, exactly
/// as published, until it is being edited: then its place shows as a ghost,
/// and the spot of whichever field has focus is lit.
class _BookPreview extends StatelessWidget {
  const _BookPreview({
    required this.page,
    required this.title,
    required this.subtitle,
    required this.author,
    required this.year,
    required this.about,
    required this.cover,
    required this.coverBytes,
    required this.coverLit,
    required this.publisher,
    required this.gameCount,
    required this.focused,
  });

  final bool page;
  final String title;
  final String subtitle;
  final String author;
  final String year;
  final String about;
  final Uri? cover;
  final Uint8List? coverBytes;
  final bool coverLit;
  final String publisher;
  final int gameCount;
  final _Field? focused;

  Widget _plate(BoxFit fit) {
    final url = cover;
    const plate = CollectionBookPlate();
    // A just-picked cover shows at once, before its upload completes.
    if (coverBytes != null) return Image.memory(coverBytes!, fit: fit);
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url.toString(),
      fit: fit,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('book_preview'),
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: colors.textPrimary.withValues(alpha: 0.08)),
      ),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: page ? _page(context) : _list(context),
      ),
    );
  }

  /// The Collections list row. A book's row credits its author; the subtitle
  /// takes that place only when no author is set, so say so when both are.
  Widget _list(BuildContext context) {
    final meta = author.isNotEmpty
        ? 'by $author'
        : subtitle.isNotEmpty
        ? subtitle
        : null;
    final shownTitle = title.isEmpty ? 'Collection title' : title;
    final note = switch (focused) {
      _Field.subtitle when author.isNotEmpty =>
        'In the list, the author’s name takes the subtitle’s place.',
      _ => null,
    };
    return Column(
      key: const ValueKey('book_preview_list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectionPlateRow(
          plate: _plate(BoxFit.cover),
          plateSize: CollectionPlateRow.eventPlate,
          compactDetails: true,
          title: shownTitle,
          meta: meta,
          metaMaxLines: 2,
          tally: gameCount > 0 ? _plural(gameCount, 'game') : null,
          semanticsLabel: [
            'Preview',
            shownTitle,
            ?meta,
            if (gameCount > 0) _plural(gameCount, 'game'),
          ].join(', '),
          trailing: Padding(
            padding: EdgeInsets.all(12.sp),
            child: SvgWidget(
              SvgAsset.starIcon,
              semanticsLabel: 'Star',
              height: 20.h,
              width: 20.w,
            ),
          ),
        ),
        if (note != null) ...[
          SizedBox(height: 10.sp),
          Text(
            note,
            style: AppTypography.textXsRegular.copyWith(
              color: context.textInk(0.6),
            ),
          ),
        ],
      ],
    );
  }

  /// The top of the About page, as `_BookAboutPage` draws it.
  Widget _page(BuildContext context) {
    final colors = context.colors;
    final secondary = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
      height: 20 / 14,
    );
    final edition = [
      if (publisher.isNotEmpty) publisher,
      if (year.isNotEmpty) year,
    ].join(' · ');
    return Column(
      key: const ValueKey('book_preview_page'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null || coverBytes != null || coverLit) ...[
              _Spot(
                lit: coverLit,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.br),
                  child: SizedBox(
                    width: 64.w,
                    height: 96.w,
                    child: _plate(BoxFit.contain),
                  ),
                ),
              ),
              SizedBox(width: 12.sp),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Spot(
                    lit: focused == _Field.title,
                    child: Text(
                      title.isEmpty ? 'Collection title' : title,
                      style: AppTypography.textSmMedium.copyWith(
                        color: title.isEmpty
                            ? context.textInk(0.35)
                            : colors.textPrimary,
                        fontSize: 20.f,
                        height: 26 / 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _line(
                    context,
                    field: _Field.subtitle,
                    value: subtitle,
                    ghost: 'Subtitle',
                    style: secondary,
                    gap: 2.sp,
                  ),
                  _line(
                    context,
                    field: _Field.author,
                    value: author.isEmpty ? '' : 'by $author',
                    ghost: 'by Author',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                    gap: 6.sp,
                    alwaysHold: true,
                  ),
                  _line(
                    context,
                    field: _Field.year,
                    value: edition,
                    ghost: edition.isEmpty ? 'Year' : edition,
                    style: secondary,
                    gap: 4.sp,
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16.sp),
        Text(
          'About this collection',
          style: AppTypography.textSmMedium.copyWith(
            color: about.isEmpty ? context.textInk(0.35) : colors.textPrimary,
            fontSize: 15.f,
            height: 20 / 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4.sp),
        _Spot(
          lit: focused == _Field.about,
          child: Text(
            about.isEmpty ? 'Your description goes here.' : about,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textSmRegular.copyWith(
              color: about.isEmpty ? context.textInk(0.35) : colors.textPrimary,
              fontSize: 15.f,
              height: 22 / 15,
            ),
          ),
        ),
      ],
    );
  }

  /// One identity line. Empty, it is absent from the page; while its field
  /// is focused (or [alwaysHold], for a field submission needs) it holds its
  /// place with a ghost.
  Widget _line(
    BuildContext context, {
    required _Field field,
    required String value,
    required String ghost,
    required TextStyle style,
    required double gap,
    bool alwaysHold = false,
  }) {
    final lit = focused == field;
    if (value.isEmpty && !lit && !alwaysHold) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: _Spot(
        lit: lit,
        child: Text(
          value.isEmpty ? ghost : value,
          style: value.isEmpty
              ? style.copyWith(color: context.textInk(0.35))
              : style,
        ),
      ),
    );
  }
}

/// A spot in the preview, tinted while its field is being edited. The tint
/// sits inside a fixed inset, so lighting one never moves the layout.
class _Spot extends StatelessWidget {
  const _Spot({required this.lit, required this.child});

  final bool lit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accentText;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 2.sp),
      transform: Matrix4.translationValues(-4.sp, 0, 0),
      decoration: BoxDecoration(
        color: lit
            ? accent.withValues(alpha: 0.14)
            : accent.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(4.br),
        border: Border.all(
          color: lit
              ? accent.withValues(alpha: 0.5)
              : accent.withValues(alpha: 0),
        ),
      ),
      child: child,
    );
  }
}
