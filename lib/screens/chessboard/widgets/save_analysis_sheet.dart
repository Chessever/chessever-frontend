import 'dart:async';

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/save_to_library_guard.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Configuration for save analysis sheet
class SaveAnalysisSheetConfig {
  final ChessBoardStateNew state;
  final ChessBoardProviderParams params;
  final BuildContext hostContext;

  const SaveAnalysisSheetConfig({
    required this.state,
    required this.params,
    required this.hostContext,
  });
}

/// Show save analysis modal bottom sheet
Future<void> showSaveAnalysisSheet({
  required BuildContext context,
  required ChessBoardStateNew state,
  required ChessBoardProviderParams params,
}) async {
  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder:
        (_) => _SaveAnalysisSheet(
          config: SaveAnalysisSheetConfig(
            state: state,
            params: params,
            hostContext: context,
          ),
        ),
  );

  await Navigator.of(context).push(route);
}

/// Preset folder colors for new folder creation
const List<Color> _folderColorPresets = [
  Color(0xFF0FB4E5), // Cyan (primary)
  Color(0xFF10B981), // Emerald
  Color(0xFFF59E0B), // Amber
  Color(0xFFEF4444), // Red
  Color(0xFF8B5CF6), // Purple
  Color(0xFFEC4899), // Pink
  Color(0xFF06B6D4), // Teal
  Color(0xFFF97316), // Orange
];

/// Outer shell widget that sets up the smooth_sheets structure
class _SaveAnalysisSheet extends ConsumerWidget {
  final SaveAnalysisSheetConfig config;

  const _SaveAnalysisSheet({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.commentEditor,
              initialOffset: const SheetOffset.proportionalToViewport(0.75),
              snapGrid: SheetSnapGrid(
                snaps: const [
                  SheetOffset.proportionalToViewport(0.55),
                  SheetOffset.proportionalToViewport(0.75),
                  SheetOffset.proportionalToViewport(0.92),
                ],
                minFlingSpeed: 600.0,
              ),
              builder: (context) => _SaveAnalysisPage(config: config),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(
          context,
          alpha: 0.97,
          borderRadius: 28.sp,
        ),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

/// Inner page widget with actual content
class _SaveAnalysisPage extends ConsumerStatefulWidget {
  final SaveAnalysisSheetConfig config;

  const _SaveAnalysisPage({required this.config});

  @override
  ConsumerState<_SaveAnalysisPage> createState() => _SaveAnalysisPageState();
}

class _SaveAnalysisPageState extends ConsumerState<_SaveAnalysisPage>
    with SingleTickerProviderStateMixin {
  late String _resolvedTitle;
  late TextEditingController _newFolderNameController;
  late FocusNode _newFolderNameFocusNode;

  // Reference database-style metadata controllers
  late TextEditingController _whiteSurnameController;
  late TextEditingController _whiteFirstNameController;
  late TextEditingController _blackSurnameController;
  late TextEditingController _blackFirstNameController;
  late TextEditingController _eventController;
  late TextEditingController _ecoController;
  late TextEditingController _whiteEloController;
  late TextEditingController _blackEloController;
  late TextEditingController _roundController;
  late TextEditingController _subroundController;
  late TextEditingController _yearController;
  late TextEditingController _monthController;
  late TextEditingController _dayController;

  LibraryFolder? _selectedFolder;
  final Map<String, LibraryFolder> _selectedFoldersById = {};
  final Set<String> _selectedFolderIds = <String>{};
  final Map<String, SavedAnalysis> _savedAnalysesByFolderId = {};
  bool _isSaving = false;
  String? _errorMessage;
  bool _isCreatingNewFolder = false;
  bool _showGameDetails = false;
  String _selectedResult = '*';
  Color _selectedFolderColor = _folderColorPresets.first;

  // Edit-existing mode: tracked once at construction so the sheet behaves
  // consistently even if the underlying SavedAnalysisData mutates mid-flow.
  bool _isEditMode = false;
  String? _existingAnalysisId;
  String? _existingSourceGameId;
  String? _initialFolderId;
  bool _hasLoadedSavedDestinations = false;
  bool _isLoadingSavedDestinations = false;
  bool _canAdoptLikedAnalysis = false;
  bool _editingLikedAnalysis = false;

  // Duplicate-as-new mode: only meaningful when _isEditMode is true. When on,
  // save inserts a new row (and re-points the open board to the copy) instead
  // of overwriting the existing analysis.
  bool _isDuplicateMode = false;

  /// Classification tags for this game (the My-Likes taxonomy). Persisted into
  /// `SavedAnalysis.tags`; pre-filled from the liked row when the game is
  /// already liked.
  List<String> _selectedTags = const <String>[];

  /// Collapsible tag section state. Tags sit above Databases now and stay
  /// expanded by default so the picker remains discoverable; users can collapse
  /// it to keep the sheet short on small phones.
  bool _tagsExpanded = true;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(
      chessBoardScreenProviderNew(widget.config.params).notifier,
    );
    final saved = notifier.savedAnalysisData;
    if (saved?.analysisId != null) {
      _isEditMode = true;
      _existingAnalysisId = saved!.analysisId;
      _existingSourceGameId = saved.sourceGameId;
      _initialFolderId = saved.folderId;
      _editingLikedAnalysis = _savedDataMatchesLoadedLike(saved);
      final dynamicTags = ref.read(likedGameTagsProvider(_likeId));
      if (dynamicTags.isNotEmpty) {
        _selectedTags = normalizeLikeTagLabels(dynamicTags);
      } else if (saved.tags.isNotEmpty) {
        _selectedTags = normalizeLikeTagLabels(saved.tags);
      }
    } else {
      // Parity with opening from My Likes: when the game wasn't opened *as* a
      // saved analysis (e.g. reached from For You / a tournament) but is
      // already liked, it lives in the Liked Games folder as a saved analysis
      // keyed by its like identity (`sourceGameId == game.likeId`). Adopt that
      // entry so the sheet pre-selects (and shows the indicator on) the Liked
      // Games folder, and a save updates the liked row instead of inserting a
      // duplicate.
      _canAdoptLikedAnalysis = true;
      _applyLikedAnalysis(
        _findLikedAnalysis(ref.read(likedGamesProvider).valueOrNull),
        notify: false,
      );
    }
    _applyInitialDynamicTags();
    _initializeControllers();
  }

  String get _likeId => widget.config.state.game.likeId;

  String get _saveSourceGameId => _existingSourceGameId ?? _likeId;

  void _selectFolder(LibraryFolder folder, {SavedAnalysis? analysis}) {
    _selectedFolderIds.add(folder.id);
    _selectedFoldersById[folder.id] = folder;
    _selectedFolder = folder;
    if (analysis != null && analysis.folderId != null) {
      _savedAnalysesByFolderId[analysis.folderId!] = analysis;
    }
  }

  void _deselectFolder(LibraryFolder folder) {
    _selectedFolderIds.remove(folder.id);
    _selectedFoldersById.remove(folder.id);
    if (_selectedFolder?.id == folder.id) {
      _selectedFolder =
          _selectedFolderIds.isEmpty
              ? null
              : _selectedFoldersById[_selectedFolderIds.last];
    }
  }

  bool _isFolderSelected(LibraryFolder folder) {
    return _selectedFolderIds.contains(folder.id);
  }

  SavedAnalysis? _preferredSavedAnalysis(List<SavedAnalysis> analyses) {
    if (analyses.isEmpty) return null;

    final existingId = _existingAnalysisId;
    if (existingId != null) {
      for (final analysis in analyses) {
        if (analysis.id == existingId) return analysis;
      }
    }

    for (final analysis in analyses) {
      final folderId = analysis.folderId;
      if (folderId == null) continue;
      final folder = _selectedFoldersById[folderId];
      if (folder != null && !folder.isLikedGames) return analysis;
    }

    return analyses.first;
  }

  Future<void> _loadSavedDestinations(List<LibraryFolder> folders) async {
    if (_hasLoadedSavedDestinations || _isLoadingSavedDestinations) return;
    _isLoadingSavedDestinations = true;

    try {
      final savedCopies = await ref
          .read(libraryRepositoryProvider)
          .getSavedAnalysesBySourceGame(sourceGameId: _saveSourceGameId);
      if (!mounted) return;

      final foldersById = {for (final folder in folders) folder.id: folder};
      setState(() {
        for (final analysis in savedCopies) {
          final folderId = analysis.folderId;
          if (folderId == null) continue;
          _savedAnalysesByFolderId[folderId] = analysis;
          final folder = foldersById[folderId];
          if (folder == null) continue;
          _selectFolder(folder, analysis: analysis);
          if (folder.isLikedGames) {
            _editingLikedAnalysis = true;
          }
        }

        final initialId = _initialFolderId;
        if (initialId != null) {
          final initialFolder = foldersById[initialId];
          if (initialFolder != null) {
            _selectFolder(initialFolder);
            if (initialFolder.isLikedGames) {
              _editingLikedAnalysis = true;
            }
          }
        }

        _hasLoadedSavedDestinations = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasLoadedSavedDestinations = true;
        _errorMessage = "Couldn't load existing database selections.";
      });
    } finally {
      _isLoadingSavedDestinations = false;
    }
  }

  SavedAnalysis? _findLikedAnalysis(List<SavedAnalysis>? likedList) {
    if (likedList == null) return null;
    for (final analysis in likedList) {
      if (analysis.sourceGameId == _likeId) {
        return analysis;
      }
    }
    return null;
  }

  void _applyLikedAnalysis(SavedAnalysis? liked, {bool notify = true}) {
    if (liked == null) return;

    void apply() {
      if (_canAdoptLikedAnalysis && liked.id.isNotEmpty) {
        _isEditMode = true;
        _existingAnalysisId = liked.id;
        _existingSourceGameId = liked.sourceGameId;
        _editingLikedAnalysis = true;
        if (_initialFolderId != liked.folderId) {
          _initialFolderId = liked.folderId;
        }
      } else if (_existingAnalysisId == liked.id) {
        _editingLikedAnalysis = true;
      }
      final folderId = liked.folderId;
      if (folderId != null) {
        _savedAnalysesByFolderId[folderId] = liked;
        _selectedFolderIds.add(folderId);
      }
      final tags = _effectiveTagsFor(liked);
      _selectedTags = normalizeLikeTagLabels(tags);
      _updateBoardSavedAnalysisTagSnapshot(_selectedTags);
    }

    if (notify && mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  List<String> _effectiveTagsFor(SavedAnalysis liked) {
    final pending = ref.read(likedGamePendingTagsProvider(_likeId));
    if (pending != null) return pending;
    final dynamicTags = ref.read(likedGameTagsProvider(_likeId));
    return dynamicTags.isNotEmpty ? dynamicTags : liked.tags;
  }

  bool _savedDataMatchesLoadedLike(SavedAnalysisData saved) {
    final analysisId = saved.analysisId;
    if (analysisId == null || analysisId.isEmpty) return false;

    final likedFolderId = ref.read(likedGamesFolderProvider).valueOrNull?.id;
    if (likedFolderId != null && saved.folderId == likedFolderId) {
      return true;
    }

    final likedRows = ref.read(likedGamesProvider).valueOrNull;
    return likedRows?.any((analysis) => analysis.id == analysisId) ?? false;
  }

  bool get _willSaveSeparateFromLikedAnalysis {
    if (!_editingLikedAnalysis) return false;
    if (_isCreatingNewFolder) return true;
    return _selectedFolderIds.any(
      (folderId) => _selectedFoldersById[folderId]?.isLikedGames == false,
    );
  }

  void _applyInitialDynamicTags() {
    final pending = ref.read(likedGamePendingTagsProvider(_likeId));
    final dynamicTags = ref.read(likedGameTagsProvider(_likeId));
    if (pending == null && dynamicTags.isEmpty) return;

    _selectedTags = normalizeLikeTagLabels(dynamicTags);
    _updateBoardSavedAnalysisTagSnapshot(_selectedTags);
  }

  void _initializeControllers() {
    final state = widget.config.state;
    final game = state.game;
    final analysisGame = state.analysisState.game;
    final metadata = analysisGame?.metadata ?? {};

    final notifier = ref.read(
      chessBoardScreenProviderNew(widget.config.params).notifier,
    );
    _resolvedTitle =
        notifier.savedAnalysisData?.title?.trim().isNotEmpty == true
            ? notifier.savedAnalysisData!.title!
            : _generateDefaultTitle();
    _newFolderNameController = TextEditingController();
    _newFolderNameFocusNode = FocusNode();

    // Parse White name
    final whiteRaw = metadata['White']?.toString() ?? game.whitePlayer.name;
    final whiteParts = whiteRaw.split(', ');
    _whiteSurnameController = TextEditingController(text: whiteParts[0]);
    _whiteFirstNameController = TextEditingController(
      text: whiteParts.length > 1 ? whiteParts[1] : '',
    );

    // Parse Black name
    final blackRaw = metadata['Black']?.toString() ?? game.blackPlayer.name;
    final blackParts = blackRaw.split(', ');
    _blackSurnameController = TextEditingController(text: blackParts[0]);
    _blackFirstNameController = TextEditingController(
      text: blackParts.length > 1 ? blackParts[1] : '',
    );

    _eventController = TextEditingController(
      text: metadata['Event']?.toString() ?? '',
    );
    _ecoController = TextEditingController(
      text: metadata['ECO']?.toString() ?? '',
    );
    _whiteEloController = TextEditingController(
      text: metadata['WhiteElo']?.toString() ?? '',
    );
    _blackEloController = TextEditingController(
      text: metadata['BlackElo']?.toString() ?? '',
    );
    _roundController = TextEditingController(
      text: metadata['Round']?.toString() ?? '',
    );
    _subroundController = TextEditingController(
      text: metadata['Subround']?.toString() ?? '',
    );

    _selectedResult = metadata['Result']?.toString() ?? '*';

    // Parse date YYYY.MM.DD
    final dateStr = metadata['Date']?.toString() ?? '';
    final dateParts = dateStr.split('.');
    _yearController = TextEditingController(
      text:
          (dateParts.isNotEmpty && dateParts[0] != '????') ? dateParts[0] : '',
    );
    _monthController = TextEditingController(
      text: (dateParts.length > 1 && dateParts[1] != '??') ? dateParts[1] : '',
    );
    _dayController = TextEditingController(
      text: (dateParts.length > 2 && dateParts[2] != '??') ? dateParts[2] : '',
    );
  }

  void _resetControllers() {
    setState(() {
      _initializeControllers();
    });
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _newFolderNameController.dispose();
    _newFolderNameFocusNode.dispose();

    _whiteSurnameController.dispose();
    _whiteFirstNameController.dispose();
    _blackSurnameController.dispose();
    _blackFirstNameController.dispose();
    _eventController.dispose();
    _ecoController.dispose();
    _whiteEloController.dispose();
    _blackEloController.dispose();
    _roundController.dispose();
    _subroundController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();

    super.dispose();
  }

  String _generateDefaultTitle() {
    final game = widget.config.state.game;
    final whiteName = game.whitePlayer.name;
    final blackName = game.blackPlayer.name;
    return '$whiteName vs $blackName';
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final title =
        _resolvedTitle.trim().isEmpty
            ? _generateDefaultTitle()
            : _resolvedTitle.trim();

    // Validate new folder name if creating one
    if (_isCreatingNewFolder) {
      final newFolderName = _newFolderNameController.text.trim();
      if (newFolderName.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter a folder name';
        });
        HapticFeedback.lightImpact();
        return;
      }
    } else if (_selectedFoldersById.isEmpty) {
      // user_saved_analyses.folder_id is NOT NULL at the DB layer; saving
      // without a folder used to succeed at insert and then orphan the row
      // (visible only via SQL, still counting toward the free-tier limit).
      setState(() {
        _errorMessage = 'Pick at least one database to save into';
      });
      HapticFeedback.lightImpact();
      return;
    } else if (_selectedFoldersById.values.any(
      (folder) => !folder.isDatabase,
    )) {
      // Library hierarchy: a Folder holds Databases, a Database holds Games.
      // A game can therefore only be saved into a database — the special
      // "Liked Games" collection is itself a games-only database, so it
      // qualifies, but a plain folder never does.
      setState(() {
        _errorMessage = 'Games can only be saved into a database.';
      });
      HapticFeedback.lightImpact();
      return;
    }

    // Updates overwrite the existing row; inserts (new analysis OR a duplicate
    // forked from an existing one) add a row and count against the free-tier
    // cap, so gate them through canSaveMoreGames.
    final saveSeparateFromLiked = _willSaveSeparateFromLikedAnalysis;
    final insertCount =
        _isCreatingNewFolder
            ? 1
            : _selectedFoldersById.keys
                .where(
                  (folderId) =>
                      _isDuplicateMode ||
                      !_savedAnalysesByFolderId.containsKey(folderId),
                )
                .length;
    if (insertCount > 0) {
      final allowed = await canSaveMoreGames(context, gamesToAdd: insertCount);
      if (!allowed || !mounted) return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Create new database if needed. A container created while saving a game
      // is always a DATABASE (it holds the game), nested inside a FOLDER — per
      // the hierarchy (Folder holds databases, Database holds games). Never a
      // root orphan, and never parented under another database or the special
      // Liked Games collection (databases can't contain nodes).
      final targetFoldersById = Map<String, LibraryFolder>.from(
        _selectedFoldersById,
      );
      if (_isCreatingNewFolder) {
        final newFolderName = _newFolderNameController.text.trim();
        final nodes = await repository.getFolders();
        LibraryFolder? parentFolder;
        for (final n in nodes) {
          if (n.isFolder) {
            parentFolder = n;
            break;
          }
        }
        // No organizational folder yet → create the default one to nest under.
        parentFolder ??= await repository.createFolder(name: 'My Folder');
        final newFolder = await repository.createFolder(
          name: newFolderName,
          color:
              '#${_selectedFolderColor.toARGB32().toRadixString(16).substring(2)}',
          parentId: parentFolder.id,
          nodeType: LibraryFolder.nodeTypeDatabase,
        );
        targetFoldersById[newFolder.id] = newFolder;
        _selectFolder(newFolder);
      }

      final state = widget.config.state;
      var analysisGame = state.analysisState.game;
      if (analysisGame == null) {
        throw Exception('No analysis game to save');
      }

      // Update metadata with form values
      final updatedMetadata = Map<String, dynamic>.from(analysisGame.metadata);

      // Combine names: Surname, First Name
      final whiteSurname = _whiteSurnameController.text.trim();
      final whiteFirst = _whiteFirstNameController.text.trim();
      final whiteFull =
          whiteFirst.isEmpty ? whiteSurname : '$whiteSurname, $whiteFirst';
      updatedMetadata['White'] = whiteFull.isEmpty ? '?' : whiteFull;

      final blackSurname = _blackSurnameController.text.trim();
      final blackFirst = _blackFirstNameController.text.trim();
      final blackFull =
          blackFirst.isEmpty ? blackSurname : '$blackSurname, $blackFirst';
      updatedMetadata['Black'] = blackFull.isEmpty ? '?' : blackFull;

      updatedMetadata['Event'] =
          _eventController.text.trim().isEmpty
              ? '?'
              : _eventController.text.trim();
      updatedMetadata['ECO'] = _ecoController.text.trim();
      updatedMetadata['WhiteElo'] = _whiteEloController.text.trim();
      updatedMetadata['BlackElo'] = _blackEloController.text.trim();
      updatedMetadata['Round'] =
          _roundController.text.trim().isEmpty
              ? '?'
              : _roundController.text.trim();
      updatedMetadata['Subround'] = _subroundController.text.trim();
      updatedMetadata['Result'] = _selectedResult;

      final year = _yearController.text.trim();
      final month = _monthController.text.trim();
      final day = _dayController.text.trim();
      if (year.isNotEmpty) {
        final m = month.isEmpty ? '??' : month.padLeft(2, '0');
        final d = day.isEmpty ? '??' : day.padLeft(2, '0');
        updatedMetadata['Date'] = '$year.$m.$d';
      } else {
        updatedMetadata['Date'] = '????.??.??';
      }

      final canonicalEvent = await repository.resolveCanonicalGameEvent(
        sourceGameId: _saveSourceGameId,
        sourceTournamentId: state.game.tourId,
      );
      final formEvent = updatedMetadata['Event']?.toString();
      final preferCanonicalEvent =
          !isReadableLibraryEventName(
            formEvent,
            whiteName: updatedMetadata['White']?.toString(),
            blackName: updatedMetadata['Black']?.toString(),
          );
      final resolvedEventName = chooseLibraryEventName(
        canonicalEventName:
            preferCanonicalEvent ? canonicalEvent?.eventName : null,
        metadataEvent: formEvent,
        site: updatedMetadata['Site']?.toString(),
        tourSlug: canonicalEvent?.tourSlug ?? state.game.tourSlug,
        tourId: state.game.tourId,
        whiteName: updatedMetadata['White']?.toString(),
        blackName: updatedMetadata['Black']?.toString(),
      );
      if (resolvedEventName != null) {
        updatedMetadata['Event'] = resolvedEventName;
      }
      final sourceTournamentId =
          canonicalEvent?.sourceTournamentId ??
          normalizeSourceTournamentId(state.game.tourId);

      analysisGame = analysisGame.copyWith(metadata: updatedMetadata);

      // Build analysis_state JSONB with navigation info
      final analysisStateJson = <String, dynamic>{
        'move_pointer': state.analysisState.movePointer,
        'is_board_flipped': state.isBoardFlipped,
      };
      final selectedTags = normalizeLikeTagLabels(_selectedTags);

      final savedResults = <SavedAnalysis>[];
      for (final entry in targetFoldersById.entries) {
        final targetFolderId = entry.key;
        final targetFolder = entry.value;
        var existing =
            _isDuplicateMode ? null : _savedAnalysesByFolderId[targetFolderId];

        if (targetFolder.isLikedGames && existing == null) {
          existing = _findLikedAnalysis(
            ref.read(likedGamesProvider).valueOrNull,
          );
          if (existing == null) {
            await ref
                .read(likedGamesProvider.notifier)
                .toggle(widget.config.state.game);
            existing = _findLikedAnalysis(
              ref.read(likedGamesProvider).valueOrNull,
            );
          }
          if (existing != null && existing.folderId != null) {
            _savedAnalysesByFolderId[existing.folderId!] = existing;
          }
        }

        if (existing != null) {
          // Update this database's existing copy.
          final savedAnalysis = SavedAnalysis(
            id: existing.id,
            userId: userId,
            folderId: targetFolderId,
            title: title,
            sourceGameId: existing.sourceGameId ?? _saveSourceGameId,
            sourceTournamentId:
                sourceTournamentId ?? existing.sourceTournamentId,
            chessGame: analysisGame,
            analysisState: analysisStateJson,
            variationComments: state.variationComments,
            moveNags: state.moveNags,
            lastViewedPosition: state.analysisState.currentMoveIndex,
            tags: selectedTags,
            notes: existing.notes,
            isFavorite: existing.isFavorite,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
          final updated = await repository.updateSavedAnalysis(savedAnalysis);
          _savedAnalysesByFolderId[targetFolderId] = updated;
          savedResults.add(updated);
          continue;
        }

        final savedAnalysis = SavedAnalysis(
          id: '', // Will be generated by database
          userId: userId,
          folderId: targetFolderId,
          title: title,
          sourceGameId: _saveSourceGameId,
          sourceTournamentId: sourceTournamentId,
          chessGame: analysisGame,
          analysisState: analysisStateJson,
          variationComments: state.variationComments,
          moveNags: state.moveNags,
          lastViewedPosition: state.analysisState.currentMoveIndex,
          tags: selectedTags,
          notes: null,
          isFavorite: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final created = await repository.createSavedAnalysis(savedAnalysis);
        _savedAnalysesByFolderId[targetFolderId] = created;
        savedResults.add(created);
      }

      // Library home cards show per-folder counts; without invalidating the
      // count family + folder stream they stay stale after a save.
      ref.invalidate(folderAnalysisCountProvider);
      ref.invalidate(libraryFoldersStreamProvider);
      unawaited(ref.read(likedGamesProvider.notifier).refresh());

      // Refresh provider's snapshot so auto-save uses the latest title/folder
      // and treats current tree as the saved baseline. A board can only attach
      // one row, so prefer the row it was already editing, then a normal
      // database copy, then My Likes.
      final attached = _preferredSavedAnalysis(savedResults);
      if (attached != null) {
        _existingAnalysisId = attached.id;
        _existingSourceGameId = attached.sourceGameId;
        _initialFolderId = attached.folderId;
        _isEditMode = true;
        _isDuplicateMode = false;
        final attachedFolder =
            attached.folderId == null
                ? null
                : targetFoldersById[attached.folderId!];
        if (attachedFolder != null) {
          _selectedFolder = attachedFolder;
          _editingLikedAnalysis = attachedFolder.isLikedGames;
        }
        ref
            .read(chessBoardScreenProviderNew(widget.config.params).notifier)
            .attachSavedAnalysisId(
              analysisId: attached.id,
              title: title,
              folderId: attached.folderId,
              tags: selectedTags,
            );
      }

      if (mounted && context.mounted) {
        HapticFeedback.mediumImpact();

        // Drop the spinner *before* attempting to pop. If the host context
        // is in a weird state (e.g. the user just bought premium through the
        // paywall and the surrounding nav stack reshuffled mid-flight), the
        // pop call below can silently no-op — without this reset the button
        // would stay stuck in the loading state even though the analysis
        // already landed in the library.
        setState(() {
          _isSaving = false;
        });

        // Show success feedback
        ScaffoldMessenger.of(widget.config.hostContext).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: context.colors.surface.withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: kPrimaryColor,
                    size: 16.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _isDuplicateMode
                        ? 'Saved a copy'
                        : (saveSeparateFromLiked
                            ? 'Saved to database'
                            : (_isEditMode
                                ? 'Game updated'
                                : 'Analysis saved successfully')),
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // Close the sheet. Prefer the host navigator (which owns the route
        // wrapping the whole PagedSheet), but fall back to the local
        // context if the host stack got reshuffled — the spinner has
        // already been reset above, so the worst case is the sheet sticks
        // around in its idle state rather than locked.
        final hostNav = Navigator.maybeOf(widget.config.hostContext);
        if (hostNav != null && hostNav.canPop()) {
          hostNav.pop();
        } else if (context.mounted) {
          Navigator.maybeOf(context)?.maybePop();
        }
      }
    } catch (e, st) {
      talker.handle(e, st);
      if (mounted) {
        setState(() {
          final verb =
              _isDuplicateMode
                  ? 'duplicate'
                  : (_isEditMode && !saveSeparateFromLiked ? 'update' : 'save');
          _errorMessage = userFacingError(
            e,
            fallback: 'Could not $verb this analysis. Please try again.',
          );
          _isSaving = false;
        });
        HapticFeedback.lightImpact();
      }
    }
  }

  /// A tap on a database row. Tapping an unselected database picks it as the
  /// save target; tapping the already-selected one toggles it off and removes
  /// the game from that database (when the game actually lives there).
  Future<void> _handleFolderTap(LibraryFolder folder) async {
    if (_isSaving) return;
    if (folder.isLikedGames) {
      final isLiked = await _resolveCurrentLikeState();
      if (!mounted) return;
      if (isLiked == null) {
        setState(() {
          _errorMessage = "Couldn't load My Likes. Please try again.";
        });
        HapticFeedback.lightImpact();
        return;
      }
      if (!isLiked) {
        final didLike = await _handleLikeFromSheet();
        if (didLike && mounted) {
          setState(() => _selectFolder(folder));
        }
        return;
      }
    }
    if (!_isFolderSelected(folder)) {
      setState(() {
        _selectFolder(folder);
        _errorMessage = null;
      });
      HapticFeedback.selectionClick();
      return;
    }
    await _removeGameFromFolder(folder);
  }

  Future<bool?> _resolveCurrentLikeState() async {
    var likedAsync = ref.read(likedGamesProvider);
    if (!likedAsync.hasValue) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });
      try {
        await ref.read(likedGamesProvider.future);
      } catch (_) {}
      if (!mounted) return null;
      likedAsync = ref.read(likedGamesProvider);
      setState(() {
        _isSaving = false;
      });
    }

    final likedList = likedAsync.valueOrNull;
    if (likedList == null) return null;
    return likedList.any((analysis) => analysis.sourceGameId == _likeId);
  }

  Future<bool> _handleLikeFromSheet() async {
    if (!_canManageLike) {
      setState(() {
        _errorMessage = "This database game can't be liked from here.";
      });
      HapticFeedback.lightImpact();
      return false;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final nowLiked = await ref
        .read(likedGamesProvider.notifier)
        .toggle(widget.config.state.game);

    ref.invalidate(folderAnalysisCountProvider);
    ref.invalidate(libraryFoldersStreamProvider);

    if (!mounted) return nowLiked;
    if (nowLiked) {
      _applyLikedAnalysis(
        _findLikedAnalysis(ref.read(likedGamesProvider).valueOrNull),
        notify: false,
      );
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      if (!nowLiked) {
        _errorMessage = "Couldn't like game. Please try again.";
      }
      _isSaving = false;
    });
    return nowLiked;
  }

  /// Deselects [folder] and removes the game from it. For the Liked Games
  /// database this is an unlike; for a normal database it deletes the saved
  /// analysis row. A folder the game isn't actually persisted in (a tentative
  /// pick on a brand-new game) just clears the selection — nothing to delete.
  Future<void> _removeGameFromFolder(LibraryFolder folder) async {
    final isLikedFolder = folder.isLikedGames;
    final persistedAnalysis = _savedAnalysesByFolderId[folder.id];
    final livesHere =
        persistedAnalysis != null ||
        (_isEditMode &&
            _existingAnalysisId != null &&
            _initialFolderId == folder.id);

    // Card reads as unselected immediately, regardless of what follows.
    setState(() {
      _deselectFolder(folder);
      _errorMessage = null;
    });

    final removeFromLiked =
        isLikedFolder && ref.read(isGameLikedProvider(_likeId));
    final removeAnalysis = (!isLikedFolder || !removeFromLiked) && livesHere;
    if (!removeFromLiked && !removeAnalysis) {
      // Nothing persisted in this folder — a plain deselect.
      HapticFeedback.selectionClick();
      return;
    }

    // Capture before the awaits — the host messenger outlives this sheet's
    // context and must not be looked up across the async gap.
    final messenger = ScaffoldMessenger.of(widget.config.hostContext);
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      if (removeFromLiked) {
        // Removal from My Likes == unlike. Route through the liked-games
        // notifier so the heart state, the My Likes list, and counts update.
        await ref
            .read(likedGamesProvider.notifier)
            .toggle(widget.config.state.game);
      } else {
        await ref
            .read(libraryRepositoryProvider)
            .deleteSavedAnalysis(persistedAnalysis?.id ?? _existingAnalysisId!);
      }

      _savedAnalysesByFolderId.remove(folder.id);
      ref.invalidate(folderAnalysisCountProvider);
      ref.invalidate(libraryFoldersStreamProvider);
      unawaited(ref.read(likedGamesProvider.notifier).refresh());

      final removedAttachedRow =
          _existingAnalysisId != null &&
          (_existingAnalysisId == persistedAnalysis?.id ||
              (_initialFolderId == folder.id && persistedAnalysis == null));
      final replacement =
          removedAttachedRow
              ? _preferredSavedAnalysis(
                _savedAnalysesByFolderId.values
                    .where(
                      (analysis) =>
                          analysis.folderId != null &&
                          _selectedFolderIds.contains(analysis.folderId),
                    )
                    .toList(),
              )
              : null;

      if (removedAttachedRow && replacement != null) {
        _existingAnalysisId = replacement.id;
        _existingSourceGameId = replacement.sourceGameId;
        _initialFolderId = replacement.folderId;
        ref
            .read(chessBoardScreenProviderNew(widget.config.params).notifier)
            .attachSavedAnalysisId(
              analysisId: replacement.id,
              title: replacement.title,
              folderId: replacement.folderId,
              tags: replacement.tags,
            );
      } else if (removedAttachedRow) {
        // No selected saved copy remains: drop edit mode and detach the board's
        // saved snapshot so auto-save won't recreate the row we just deleted.
        ref
            .read(chessBoardScreenProviderNew(widget.config.params).notifier)
            .detachSavedAnalysis();
      }

      if (!mounted) return;
      setState(() {
        if (removedAttachedRow && replacement == null) {
          _isEditMode = false;
          _isDuplicateMode = false;
          _existingAnalysisId = null;
          _existingSourceGameId = null;
          _initialFolderId = null;
        } else if (replacement != null) {
          _isEditMode = true;
          _isDuplicateMode = false;
          _selectedFolder =
              replacement.folderId == null
                  ? null
                  : _selectedFoldersById[replacement.folderId!];
        }
        _editingLikedAnalysis =
            _selectedFolder?.isLikedGames == true ||
            _selectedFolderIds.any(
              (folderId) =>
                  _selectedFoldersById[folderId]?.isLikedGames == true,
            );
        // Don't let the folder-list pre-select logic re-select the row we
        // just emptied on the next data build.
        _isSaving = false;
      });

      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.br),
          ),
          content: Text(
            'Removed from ${folder.displayName}',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to remove from ${folder.displayName}.';
      });
      HapticFeedback.lightImpact();
    }
  }

  void _toggleCreateNewFolder() {
    setState(() {
      _isCreatingNewFolder = !_isCreatingNewFolder;
      if (_isCreatingNewFolder) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _newFolderNameFocusNode.requestFocus();
          }
        });
      }
    });
    HapticFeedback.selectionClick();
  }

  void _toggleDuplicateMode() {
    setState(() {
      _isDuplicateMode = !_isDuplicateMode;
      if (_isDuplicateMode) {
        // Force a fresh folder choice — duplicating into the same database is
        // allowed, but starting with the originating folder pre-selected is a
        // foot-gun (looks like an update target).
        _selectedFolder = null;
        _selectedFolderIds.clear();
        _selectedFoldersById.clear();
      } else {
        // Returning to update mode: re-apply the originating folder pre-select
        // on the next data build.
        _hasLoadedSavedDestinations = false;
      }
      _errorMessage = null;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(_foldersProvider);
    ref.listen<List<String>>(likedGameTagsProvider(_likeId), (previous, next) {
      _applySelectedTags(next);
    });
    ref.listen<AsyncValue<List<SavedAnalysis>>>(likedGamesProvider, (_, next) {
      final liked = _findLikedAnalysis(next.valueOrNull);
      if (liked == null) return;
      _applyLikedAnalysis(liked);
    });

    // CRITICAL: Wrap with Material to prevent yellow underline bug
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                _buildDragHandle(),

                // Header
                _buildHeader()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 50.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 24.h),

                // Game Details (PGN Headers)
                _buildGameDetailsSection()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 100.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 24.h),

                // Tag (My-Likes classification) — above Databases per PM feedback.
                _buildTagsSection()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 150.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 24.h),

                // Folder section (Databases)
                _buildFolderSection(foldersAsync)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 175.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                // Error messages
                if (_errorMessage != null) ...[
                  SizedBox(height: 16.h),
                  _buildErrorMessage()
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .shake(hz: 2, curve: Curves.easeInOut),
                ],

                SizedBox(height: 28.h),

                // Action buttons
                _buildActionButtons()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 200.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 12.h),
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2.br),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final saveSeparateFromLiked = _willSaveSeparateFromLikedAnalysis;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon with gradient background
              Container(
                padding: EdgeInsets.all(10.sp),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withValues(alpha: 0.2),
                      kPrimaryColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _isDuplicateMode || saveSeparateFromLiked
                      ? Icons.content_copy_rounded
                      : (_isEditMode
                          ? Icons.edit_rounded
                          : Icons.bookmark_add_rounded),
                  color: kPrimaryColor,
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDuplicateMode || saveSeparateFromLiked
                          ? 'Save as Copy'
                          : (_isEditMode
                              ? 'Edit Game Details'
                              : 'Save Analysis'),
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _isDuplicateMode
                          ? 'Fork into a new database'
                          : (saveSeparateFromLiked
                              ? 'Keep the like and save to a database'
                              : (_isEditMode
                                  ? 'Update title, folder & metadata'
                                  : 'Keep your variations & comments')),
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isEditMode && !_editingLikedAnalysis) ...[
            SizedBox(height: 16.h),
            _buildModeToggle(),
          ],
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeSegment(
              label: 'Update',
              icon: Icons.check_rounded,
              selected: !_isDuplicateMode,
              onTap:
                  _isSaving || !_isDuplicateMode ? null : _toggleDuplicateMode,
            ),
          ),
          Expanded(
            child: _modeSegment(
              label: 'Save Copy',
              icon: Icons.content_copy_rounded,
              selected: _isDuplicateMode,
              onTap:
                  _isSaving || _isDuplicateMode ? null : _toggleDuplicateMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color:
              selected
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                selected
                    ? kPrimaryColor.withValues(alpha: 0.35)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14.sp,
              color:
                  selected
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.5),
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(
                color:
                    selected
                        ? kPrimaryColor
                        : context.colors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameDetailsSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _showGameDetails = !_showGameDetails);
              HapticFeedback.selectionClick();
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color: context.colors.textPrimary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
                    size: 20.sp,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'Game Details',
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.9,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _showGameDetails ? 'Hide' : 'Show',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kPrimaryColor,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    _showGameDetails
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kPrimaryColor,
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),
          if (_showGameDetails) ...[
            SizedBox(height: 16.h),

            // White Player
            _buildPlayerSection(
              'White',
              _whiteSurnameController,
              _whiteFirstNameController,
            ),
            SizedBox(height: 16.h),

            // Black Player
            _buildPlayerSection(
              'Black',
              _blackSurnameController,
              _blackFirstNameController,
            ),
            SizedBox(height: 16.h),

            _buildMetadataField('Tournament', _eventController),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(child: _buildMetadataField('ECO', _ecoController)),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildMetadataField('Result', null, isResult: true),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildMetadataField(
                    'White Elo',
                    _whiteEloController,
                    isNumeric: true,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildMetadataField(
                    'Black Elo',
                    _blackEloController,
                    isNumeric: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(child: _buildMetadataField('Round', _roundController)),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildMetadataField('Subround', _subroundController),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            _buildDateField(),
            SizedBox(height: 16.h),

            // Reset button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSaving ? null : _resetControllers,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 14.sp,
                  color: context.colors.textPrimary.withValues(alpha: 0.4),
                ),
                label: Text(
                  'Reset Details',
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerSection(
    String label,
    TextEditingController surname,
    TextEditingController first,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6.h),
        Row(
          children: [
            Expanded(child: _buildSmallTextField('Surname', surname)),
            SizedBox(width: 8.w),
            Expanded(child: _buildSmallTextField('First name', first)),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallTextField(String hint, TextEditingController controller) {
    return Container(
      height: 40.h,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: TextField(
        controller: controller,
        enabled: !_isSaving,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.2),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        ),
      ),
    );
  }

  Widget _buildMetadataField(
    String label,
    TextEditingController? controller, {
    bool isNumeric = false,
    bool isResult = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
        SizedBox(height: 6.h),
        Container(
          height: 44.h,
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10.br),
            border: Border.all(
              color: context.colors.textPrimary.withValues(alpha: 0.06),
            ),
          ),
          child:
              isResult
                  ? _buildResultDropdown()
                  : TextField(
                    controller: controller,
                    enabled: !_isSaving,
                    keyboardType:
                        isNumeric ? TextInputType.number : TextInputType.text,
                    inputFormatters:
                        isNumeric
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : null,
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 10.h,
                      ),
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildResultDropdown() {
    final results = ['1-0', '0-1', '1/2-1/2', '+:-', '-:+', '=:=', '0-0', '*'];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedResult,
          isExpanded: true,
          dropdownColor: context.colors.surface,
          icon: Icon(
            Icons.arrow_drop_down,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary,
          ),
          onChanged:
              _isSaving
                  ? null
                  : (String? newValue) {
                    if (newValue != null) {
                      setState(() => _selectedResult = newValue);
                    }
                  },
          items:
              results.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date (YYYY.MM.DD)',
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
        SizedBox(height: 6.h),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildSmallTextField('YYYY', _yearController),
            ),
            SizedBox(width: 6.w),
            Expanded(child: _buildSmallTextField('MM', _monthController)),
            SizedBox(width: 6.w),
            Expanded(child: _buildSmallTextField('DD', _dayController)),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap:
                  _isSaving
                      ? null
                      : () {
                        final now = DateTime.now();
                        setState(() {
                          _yearController.text = now.year.toString();
                          _monthController.text = now.month.toString().padLeft(
                            2,
                            '0',
                          );
                          _dayController.text = now.day.toString().padLeft(
                            2,
                            '0',
                          );
                        });
                        HapticFeedback.lightImpact();
                      },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Today',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kPrimaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Whether the like toggle should be offered for this game — mirrors the
  /// board's rules: only likeable sources, and never an own-database saved game
  /// (which would just mirror a confusing duplicate into Liked Games). Games
  /// opened from the Liked Games database itself stay manageable so unlike works.
  bool get _canManageLike {
    final game = widget.config.state.game;
    final source = game.source;
    final likeable =
        source == GameSource.supabase ||
        source == GameSource.gamebase ||
        source == GameSource.twic ||
        source == GameSource.savedAnalysis;
    if (!likeable) return false;

    if (source == GameSource.savedAnalysis) {
      final saved =
          ref
              .read(chessBoardScreenProviderNew(widget.config.params).notifier)
              .savedAnalysisData;
      if (saved?.analysisId != null) {
        final likedFolderId =
            ref.read(likedGamesFolderProvider).valueOrNull?.id;
        // Fail closed: unknown liked folder, or a folder that isn't it, means
        // this came from one of the user's own databases — not likeable here.
        if (likedFolderId == null || saved!.folderId != likedFolderId) {
          return false;
        }
      }
    }
    return true;
  }

  Widget _buildTagsSection() {
    final colors = context.colors;
    final selectedCount = _selectedTags.length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _tagsExpanded = !_tagsExpanded);
            },
            child: Row(
              children: [
                Text(
                  'Tag',
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary.withValues(alpha: 0.8),
                    letterSpacing: 0.3,
                  ),
                ),
                if (selectedCount > 0) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 7.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: colors.textPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999.br),
                    ),
                    child: Text(
                      '$selectedCount',
                      style: AppTypography.textXsMedium.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (selectedCount > 0)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        _isSaving
                            ? null
                            : () {
                              _handleTagSelection(null);
                            },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.w,
                        vertical: 2.h,
                      ),
                      child: Text(
                        'Clear',
                        style: AppTypography.textXsMedium.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                SizedBox(width: 2.w),
                AnimatedRotation(
                  turns: _tagsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20.sp,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child:
                _tagsExpanded
                    ? Padding(
                      padding: EdgeInsets.only(top: 14.h),
                      child: Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: [
                          for (final tag in kLikeTags)
                            () {
                              final selected = _selectedTags.contains(
                                tag.label,
                              );
                              return _TagChip(
                                tag: tag,
                                selected: selected,
                                onTap:
                                    _isSaving
                                        ? null
                                        : () {
                                          _handleTagSelection(tag.label);
                                        },
                              );
                            }(),
                        ],
                      ),
                    )
                    : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTagSelection(String? tag) async {
    if (_isSaving) return;

    final nextTags = _nextSelectedTags(tag);
    if (_sameTagLabels(_selectedTags, nextTags)) return;

    HapticFeedback.selectionClick();
    setState(() {
      _selectedTags = nextTags;
      _errorMessage = null;
    });
    _updateBoardSavedAnalysisTagSnapshot(nextTags);

    // Tags persist immediately only for liked games (the Liked Games row). For
    // an own-database game in edit mode the tag rides along with the next Save
    // (see _handleSave), so don't push it through the liked-games path here.
    if (!_canManageLike) return;

    // Tags only have meaning on a liked game, so choosing tags for a game that
    // isn't liked yet implies the like. Fire it first — setTagsForLikeId waits
    // for the in-flight toggle before writing.
    if (nextTags.isNotEmpty && !ref.read(isGameLikedProvider(_likeId))) {
      unawaited(
        ref.read(likedGamesProvider.notifier).toggle(widget.config.state.game),
      );
    }

    final persisted = await ref
        .read(likedGamesProvider.notifier)
        .setTagsForLikeId(_likeId, nextTags);
    if (persisted || !mounted) return;

    final latestTags = normalizeLikeTagLabels(
      ref.read(likedGameTagsProvider(_likeId)),
    );
    setState(() {
      _selectedTags = latestTags;
      _errorMessage = "Couldn't update tags. Please try again.";
    });
    _updateBoardSavedAnalysisTagSnapshot(_selectedTags);
  }

  void _applySelectedTags(List<String> tags) {
    final nextTags = normalizeLikeTagLabels(tags);
    if (_sameTagLabels(_selectedTags, nextTags)) return;
    if (!mounted) {
      _selectedTags = nextTags;
      return;
    }
    setState(() => _selectedTags = nextTags);
    _updateBoardSavedAnalysisTagSnapshot(nextTags);
  }

  List<String> _nextSelectedTags(String? tag) {
    if (tag == null) return const <String>[];
    final next = List<String>.from(_selectedTags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    return normalizeLikeTagLabels(next);
  }

  bool _sameTagLabels(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _updateBoardSavedAnalysisTagSnapshot(List<String> tags) {
    ref
        .read(chessBoardScreenProviderNew(widget.config.params).notifier)
        .updateSavedAnalysisTagsSnapshot(tags);
  }

  Widget _buildFolderSection(AsyncValue<List<LibraryFolder>> foldersAsync) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Save to Database',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.8),
                  letterSpacing: 0.3,
                ),
              ),
              // Create new folder toggle
              GestureDetector(
                onTap: _isSaving ? null : _toggleCreateNewFolder,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _isCreatingNewFolder
                            ? kPrimaryColor.withValues(alpha: 0.15)
                            : context.colors.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                    borderRadius: BorderRadius.circular(20.br),
                    border: Border.all(
                      color:
                          _isCreatingNewFolder
                              ? kPrimaryColor.withValues(alpha: 0.4)
                              : context.colors.textPrimary.withValues(
                                alpha: 0.1,
                              ),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCreatingNewFolder
                            ? Icons.folder_outlined
                            : Icons.create_new_folder_outlined,
                        size: 14.sp,
                        color:
                            _isCreatingNewFolder
                                ? kPrimaryColor
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.6,
                                ),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        _isCreatingNewFolder
                            ? 'Choose Existing'
                            : 'New Database',
                        style: AppTypography.textXsMedium.copyWith(
                          color:
                              _isCreatingNewFolder
                                  ? kPrimaryColor
                                  : context.colors.textPrimary.withValues(
                                    alpha: 0.6,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),

          // Content based on mode
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              );
            },
            child:
                _isCreatingNewFolder
                    ? _buildNewFolderInput(key: const ValueKey('new_folder'))
                    : _buildFolderList(
                      foldersAsync,
                      key: const ValueKey('folder_list'),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewFolderInput({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder name input
        Container(
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(
              color:
                  _newFolderNameFocusNode.hasFocus
                      ? kPrimaryColor.withValues(alpha: 0.5)
                      : context.colors.textPrimary.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _newFolderNameController,
            focusNode: _newFolderNameFocusNode,
            enabled: !_isSaving,
            maxLength: 50,
            style: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Folder name',
              hintStyle: AppTypography.textMdRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16.w,
                vertical: 14.h,
              ),
              counterText: '',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 14.w, right: 10.w),
                child: Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: _selectedFolderColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: _selectedFolderColor,
                    size: 18.sp,
                  ),
                ),
              ),
              prefixIconConstraints: BoxConstraints(
                minWidth: 50.w,
                minHeight: 36.h,
              ),
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),

        SizedBox(height: 14.h),

        // Color picker
        Text(
          'Folder Color',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
        SizedBox(height: 10.h),
        SizedBox(
          height: 36.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _folderColorPresets.length,
            separatorBuilder: (_, __) => SizedBox(width: 10.w),
            itemBuilder: (context, index) {
              final color = _folderColorPresets[index];
              final isSelected = _selectedFolderColor == color;

              return GestureDetector(
                onTap:
                    _isSaving
                        ? null
                        : () {
                          setState(() {
                            _selectedFolderColor = color;
                          });
                          HapticFeedback.selectionClick();
                        },
                child: SingleMotionBuilder(
                  motion: const CupertinoMotion.smooth(),
                  value: isSelected ? 1.0 : 0.0,
                  builder: (context, value, child) {
                    final animValue = value.clamp(0.0, 1.0).toDouble();
                    return Transform.scale(
                      scale: 1.0 + (animValue * 0.15),
                      child: Container(
                        width: 36.w,
                        height: 36.h,
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: 0.2 + (animValue * 0.3),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(
                              alpha: 0.5 + (animValue * 0.5),
                            ),
                            width: 2 + animValue,
                          ),
                          boxShadow:
                              isSelected
                                  ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                  : null,
                        ),
                        child:
                            isSelected
                                ? Icon(
                                  Icons.check_rounded,
                                  color: color,
                                  size: 18.sp,
                                )
                                : null,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderList(
    AsyncValue<List<LibraryFolder>> foldersAsync, {
    Key? key,
  }) {
    return foldersAsync.when(
      data: (folders) {
        if (!_hasLoadedSavedDestinations) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_loadSavedDestinations(folders));
            }
          });
        }
        // Sort folders hierarchically: parents first, then their children
        final sortedFolders = _sortFoldersHierarchically(folders);
        return _buildFolderListContent(sortedFolders, key: key);
      },
      loading: () => _buildFolderListLoading(key: key),
      error: (e, _) => _buildFolderListError(e, key: key),
    );
  }

  /// Sorts folders such that children follow their parents based on parentId.
  List<LibraryFolder> _sortFoldersHierarchically(List<LibraryFolder> folders) {
    final Map<String?, List<LibraryFolder>> groupedByParent = {};
    for (final folder in folders) {
      groupedByParent.putIfAbsent(folder.parentId, () => []).add(folder);
    }

    final List<LibraryFolder> sorted = [];

    void addFolders(String? parentId) {
      final children = groupedByParent[parentId] ?? [];
      // Sort children by orderIndex
      children.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final folder in children) {
        sorted.add(folder);
        addFolders(folder.id);
      }
    }

    addFolders(null);

    // Handle orphans (shouldn't happen with correct DB state but good for robustness)
    if (sorted.length < folders.length) {
      final sortedIds = sorted.map((f) => f.id).toSet();
      for (final folder in folders) {
        if (!sortedIds.contains(folder.id)) {
          sorted.add(folder);
        }
      }
    }

    return sorted;
  }

  Widget _buildFolderListContent(List<LibraryFolder> folders, {Key? key}) {
    // The My Likes database is shown here like any other; flag it as already
    // holding this game when it's liked, so the row reads as "already in" —
    // replacing the separate liked-toggle row that used to live above.
    final isLiked = ref.watch(isGameLikedProvider(_likeId));

    // If no folders exist, prompt user to create one
    if (folders.isEmpty) {
      return Container(
        key: key,
        padding: EdgeInsets.all(20.sp),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.br),
              ),
              child: Icon(
                Icons.dataset_outlined,
                color: kPrimaryColor,
                size: 28.sp,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'No databases yet',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.9),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Create a database to store your games',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            GestureDetector(
              onTap: _isSaving ? null : _toggleCreateNewFolder,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16.sp, color: kPrimaryColor),
                    SizedBox(width: 6.w),
                    Text(
                      'Create Database',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show folders list (without "No folder" option)
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.br),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              folders.asMap().entries.map((entry) {
                final index = entry.key;
                final folder = entry.value;
                final isSelected = _isFolderSelected(folder);
                final isLast = index == folders.length - 1;
                // Only nest a row when its parent is actually present in this
                // list. The sheet lists databases only (parent folders are
                // filtered out), so a database whose folder is absent must
                // render flat — otherwise it draws indented under whatever row
                // precedes it (e.g. "My Database" looking like a child of
                // "My Likes").
                final isChildNode =
                    folder.parentId != null &&
                    folders.any((f) => f.id == folder.parentId);

                return Column(
                  children: [
                    _FolderListItem(
                      folder: folder,
                      isSelected: isSelected,
                      isDisabled: _isSaving,
                      isChildNode: isChildNode,
                      showLikedBadge: folder.isLikedGames && isLiked,
                      onTap: () => _handleFolderTap(folder),
                    ),
                    if (!isLast)
                      Container(
                        height: 1,
                        margin: EdgeInsets.only(
                          left: isChildNode ? 80.w : 56.w,
                        ),
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.05,
                        ),
                      ),
                  ],
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildFolderListLoading({Key? key}) {
    return Container(
      key: key,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18.w,
            height: 18.h,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                kPrimaryColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Text(
            'Loading folders...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderListError(Object error, {Key? key}) {
    return Container(
      key: key,
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.sp),
            decoration: BoxDecoration(
              color: kRedColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: kRedColor,
              size: 18.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Failed to load folders',
              style: AppTypography.textSmRegular.copyWith(
                color: kRedColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.all(14.sp),
        decoration: BoxDecoration(
          color: kRedColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14.br),
          border: Border.all(color: kRedColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.sp),
              decoration: BoxDecoration(
                color: kRedColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: kRedColor,
                size: 16.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: AppTypography.textSmRegular.copyWith(
                  color: kRedColor.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    // Save is enabled only when:
    // - Not currently saving, AND
    // - A folder is selected, OR new folder mode is on with a non-empty name
    final trimmedNewFolderName = _newFolderNameController.text.trim();
    final hasExistingFolder = _selectedFoldersById.isNotEmpty;
    final hasValidNewFolderName =
        _isCreatingNewFolder && trimmedNewFolderName.isNotEmpty;
    final canSave = !_isSaving && (hasValidNewFolderName || hasExistingFolder);
    final saveSeparateFromLiked = _willSaveSeparateFromLikedAnalysis;
    final selectedDatabaseCount =
        _selectedFoldersById.length + (hasValidNewFolderName ? 1 : 0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Row(
        children: [
          // Cancel button
          Expanded(
            child: GestureDetector(
              onTap:
                  _isSaving
                      ? null
                      : () {
                        HapticFeedback.lightImpact();
                        Navigator.of(widget.config.hostContext).pop();
                      },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14.br),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Save button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: canSave ? _handleSave : null,
              child: SingleMotionBuilder(
                motion: const CupertinoMotion.smooth(),
                value: _isSaving ? 0.95 : 1.0,
                builder: (context, value, child) {
                  final scale = value.clamp(0.0, 1.0).toDouble();
                  return Transform.scale(
                    scale: scale,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      decoration: BoxDecoration(
                        gradient:
                            canSave
                                ? LinearGradient(
                                  colors: [
                                    kPrimaryColor,
                                    kPrimaryColor.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                                : null,
                        color:
                            canSave
                                ? null
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                        borderRadius: BorderRadius.circular(14.br),
                        boxShadow:
                            canSave
                                ? [
                                  BoxShadow(
                                    color: kPrimaryColor.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                                : null,
                      ),
                      child: Center(
                        child:
                            _isSaving
                                ? SizedBox(
                                  width: 20.w,
                                  height: 20.h,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      context.colors.textPrimary,
                                    ),
                                  ),
                                )
                                : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isDuplicateMode || saveSeparateFromLiked
                                          ? Icons.content_copy_rounded
                                          : (_isEditMode
                                              ? Icons.check_rounded
                                              : Icons.bookmark_add_rounded),
                                      color:
                                          canSave
                                              ? context.colors.textPrimary
                                              : context.colors.textPrimary
                                                  .withValues(alpha: 0.3),
                                      size: 18.sp,
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(
                                      canSave
                                          ? (_isDuplicateMode
                                              ? 'Save Copy'
                                              : (saveSeparateFromLiked
                                                  ? (selectedDatabaseCount > 1
                                                      ? 'Save to Databases'
                                                      : 'Save to Database')
                                                  : (_isEditMode
                                                      ? 'Update Game'
                                                      : 'Save Analysis')))
                                          : _isCreatingNewFolder
                                          ? 'Name your database'
                                          : 'Select a Database',
                                      style: AppTypography.textSmBold.copyWith(
                                        color:
                                            canSave
                                                ? context.colors.textPrimary
                                                : context.colors.textPrimary
                                                    .withValues(alpha: 0.3),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderListItem extends ConsumerWidget {
  final LibraryFolder folder;
  final bool isSelected;
  final bool isDisabled;
  final bool isChildNode;
  final bool showLikedBadge;
  final VoidCallback onTap;

  const _FolderListItem({
    required this.folder,
    required this.isSelected,
    required this.isDisabled,
    this.isChildNode = false,
    this.showLikedBadge = false,
    required this.onTap,
  });

  Color _parseColorString(String colorString) {
    try {
      final hex = colorString.replaceAll('#', '');
      final colorValue = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(colorValue, radix: 16));
    } catch (e) {
      return kPrimaryColor;
    }
  }

  String _formatGameCount(int count) {
    if (count == 0) return 'Empty';
    if (count == 1) return '1 game';
    return '${formatCompactCount(count)} games';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folderColor = _parseColorString(folder.color);
    final countAsync = ref.watch(folderAnalysisCountProvider(folder.id));

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.smooth(),
        value: isSelected ? 1.0 : 0.0,
        builder: (context, value, child) {
          final animValue = value.clamp(0.0, 1.0).toDouble();
          return Container(
            padding: EdgeInsets.only(
              left: 14.w + (isChildNode ? 24.w : 0),
              right: 14.w,
              top: 12.h,
              bottom: 12.h,
            ),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                kPrimaryColor.withValues(alpha: 0.08),
                animValue,
              ),
            ),
            child: Row(
              children: [
                if (isChildNode) ...[
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 16.sp,
                    color: context.colors.textPrimary.withValues(alpha: 0.3),
                  ),
                  SizedBox(width: 8.w),
                ],
                // Folder icon
                Container(
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: folderColor.withValues(
                      alpha: 0.12 + (animValue * 0.08),
                    ),
                    borderRadius: BorderRadius.circular(10.br),
                    border: Border.all(
                      color: folderColor.withValues(
                        alpha: 0.2 + (animValue * 0.2),
                      ),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    folder.isLikedGames
                        ? Icons.favorite_rounded
                        : Icons.dataset_rounded,
                    size: 18.sp,
                    color:
                        folder.isLikedGames
                            ? context.colors.danger
                            : folderColor,
                  ),
                ),
                SizedBox(width: 14.w),

                // Database name + game count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              folder.displayName,
                              style: AppTypography.textSmMedium.copyWith(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (showLikedBadge) ...[
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.danger.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(20.br),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.favorite_rounded,
                                    size: 10.sp,
                                    color: context.colors.danger,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Liked',
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: context.colors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        countAsync.when(
                          data: _formatGameCount,
                          loading: () => '…',
                          error: (_, __) => '',
                        ),
                        style: AppTypography.textXsRegular.copyWith(
                          color: const Color(0xFFA1A1A1),
                          height: 16 / 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Selection indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 22.w,
                  height: 22.h,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? kPrimaryColor
                            : context.colors.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isSelected
                              ? kPrimaryColor
                              : context.colors.textPrimary.withValues(
                                alpha: 0.15,
                              ),
                      width: 2,
                    ),
                  ),
                  child:
                      isSelected
                          ? Icon(
                            Icons.check_rounded,
                            size: 14.sp,
                            color: context.colors.textPrimary,
                          )
                          : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Provider to fetch folders for the current user. Databases only, with the
/// Liked Games database pinned to the top of the list — it's the default
/// destination for liked games and PM wants it always reachable without
/// scrolling.
final _foldersProvider = FutureProvider.autoDispose<List<LibraryFolder>>((
  ref,
) async {
  final repository = ref.watch(libraryRepositoryProvider);
  final folders = await repository.getFolders();
  final databases = folders
      .where((folder) => folder.isDatabase)
      .toList(growable: false);
  // Stable sort: liked first, otherwise preserve repo order.
  final sorted = [...databases]..sort((a, b) {
    if (a.isLikedGames == b.isLikedGames) return 0;
    return a.isLikedGames ? -1 : 1;
  });
  return sorted;
});

/// A selectable tag chip. Motor springs a subtle pop on selection and the fill
/// / border ease from neutral to the tag's accent.
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final LikeTag tag;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: selected ? 1.0 : 0.0,
      builder: (context, t, child) {
        return Transform.scale(
          scale: 1.0 + 0.06 * t,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Color.lerp(
                  colors.textPrimary.withValues(alpha: 0.05),
                  tag.color.withValues(alpha: 0.22),
                  t,
                ),
                borderRadius: BorderRadius.circular(20.br),
                border: Border.all(
                  color:
                      Color.lerp(
                        colors.textPrimary.withValues(alpha: 0.1),
                        tag.color.withValues(alpha: 0.75),
                        t,
                      )!,
                  width: 1,
                ),
              ),
              child: Text(
                tag.label,
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      selected
                          ? colors.textPrimary
                          : colors.textPrimary.withValues(alpha: 0.7),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
