import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart'
    show twicDatabaseTotalGamesProvider;
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart'
    show miniaturesTotalCountProvider;
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

// The Library tab, as My Space's Library row needs it: the same destinations
// in the same order, opened, counted and managed the same way. Everything
// here reads the Library's own providers and repository; nothing is cached or
// stored on the My Space side, so the row is a live mirror of the tab.

/// The Library tab's list, as it stands: whether it has loaded yet, and the
/// destinations in the tab's own order.
typedef SpaceLibraryFolders = ({List<LibraryFolder> folders, bool settled});

/// The Library tab's order: the account's Liked Games collection, the
/// ChessEver Database, Miniatures, then every other root destination, owned
/// before subscribed, exactly as `LibraryScreen` pins and lists them.
@visibleForTesting
List<LibraryFolder> spaceLibraryDisplayOrder(List<LibraryFolder> roots) {
  final likedIdx = roots.indexWhere((f) => f.isLikedGames);
  final rest = likedIdx == -1
      ? roots
      : (List<LibraryFolder>.of(roots)..removeAt(likedIdx));
  return [
    if (likedIdx != -1) roots[likedIdx],
    kTwicFolder,
    kMiniaturesFolder,
    ...rest.where((f) => f.id != kTwicBookId && f.id != kMiniaturesBookId),
  ];
}

/// The Library row's destinations. A guest's Library is the two built-in
/// databases; an account's waits for its own list before it counts as
/// settled, so nothing on the row pops in during a cold start.
final spaceLibraryFoldersProvider = Provider.autoDispose<SpaceLibraryFolders>((
  ref,
) {
  final userId = ref.watch(libraryFolderAuthenticatedUserIdProvider);
  if (userId == null) {
    return (folders: [kTwicFolder, kMiniaturesFolder], settled: true);
  }
  final owned = ref.watch(libraryFoldersStreamProvider);
  final subscribed = ref.watch(subscribedBooksProvider);
  final roots = [
    ...owned.valueOrNull ?? const <LibraryFolder>[],
    ...subscribed.valueOrNull ?? const <LibraryFolder>[],
  ].where((f) => f.parentId == null).toList();
  final settled =
      (owned.hasValue || owned.hasError) &&
      (subscribed.hasValue || subscribed.hasError);
  return (folders: spaceLibraryDisplayOrder(roots), settled: settled);
});

bool spaceIsProtectedFolder(LibraryFolder folder) =>
    folder.id == kTwicBookId ||
    folder.id == kMiniaturesBookId ||
    folder.isLikedGames;

/// The destination as a My Space shortcut, keyed exactly as the Library
/// card's own "Add to My Space" keys it, so a pin of the same destination is
/// the same shortcut. The built-in collections map to their own kinds.
SpaceShortcut spaceLibraryFolderDraft(LibraryFolder folder) {
  if (folder.isLikedGames) {
    return SpaceShortcut.draft(
      kind: SpaceShortcutKind.likes,
      targetId: 'me',
      title: folder.displayName,
    );
  }
  if (folder.id == kMiniaturesBookId) {
    return SpaceShortcut.draft(
      kind: SpaceShortcutKind.miniatures,
      targetId: 'today',
      title: folder.displayName,
      subtitle: 'Short decisive games',
    );
  }
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.folder,
    targetId: folder.id,
    title: folder.displayName,
    subtitle: folder.id == kTwicBookId
        ? 'Master games'
        : folder.isSubscribed && folder.ownerDisplayName != null
        ? 'by ${folder.ownerDisplayName}'
        : folder.isFolder
        ? 'Folder'
        : 'Database',
    params: {
      'nodeType': folder.nodeType,
      if (folder.isSubscribed) 'subscribed': true,
    },
  );
}

/// Opens [folder] where the Library tab opens it.
Future<void> spaceOpenLibraryFolder(
  BuildContext context,
  LibraryFolder folder,
) async {
  HapticFeedbackService.cardTap();
  final Widget screen;
  if (folder.id == kTwicBookId) {
    screen = const TwicContentsScreen();
  } else if (folder.id == kMiniaturesBookId) {
    screen = const MiniaturesScreen();
  } else if (folder.isLikedGames) {
    screen = const MyLikesScreen();
  } else {
    screen = FolderContentsScreen(folder: folder);
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
}

String _gameCount(int count) {
  if (count == 0) return 'Empty database';
  if (count == 1) return '1 game';
  return '${formatCompactCount(count)} games';
}

String _childCount(int count) {
  if (count == 0) return 'Empty folder';
  if (count == 1) return '1 item';
  return '$count items';
}

/// The Library card's second line, live: game or item count, the master
/// games total or the miniature count. A subscribed database reads as its
/// card does, its owner and then its count.
class SpaceLibraryCountText extends ConsumerWidget {
  const SpaceLibraryCountText({super.key, required this.folder});

  final LibraryFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String text;
    if (folder.id == kTwicBookId) {
      final count = ref.watch(twicDatabaseTotalGamesProvider).valueOrNull ?? 0;
      text = count > 0
          ? '${formatCompactCount(count)} master games'
          : 'Master games';
    } else if (folder.id == kMiniaturesBookId) {
      final count = ref.watch(miniaturesTotalCountProvider).valueOrNull ?? 0;
      text = count > 0
          ? '${formatCompactCount(count)} miniatures'
          : 'Short decisive games';
    } else if (folder.isFolder) {
      text = _childCount(
        ref.watch(childLibraryFoldersProvider(folder.id)).length,
      );
    } else {
      final count = ref.watch(folderAnalysisCountProvider(folder.id));
      text = count.hasValue ? _gameCount(count.value!) : 'Database';
    }
    final owner = folder.isSubscribed ? folder.ownerDisplayName : null;
    if (owner == null) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    // One line each, so a long owner name cannot push the count off the tile.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('by $owner', maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// The Library card's own long-press actions for [folder], less its My Space
/// row (the destination is already on the row). Built-in collections have
/// nothing to manage. Everything the actions need is taken up front: they
/// run after the menu closes, when the tile may already be gone.
List<LibraryMenuAction> spaceLibraryFolderActions(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder folder,
) {
  if (spaceIsProtectedFolder(folder)) return const [];
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The container outlives the tile, which a delete or unsubscribe removes
  // before the action has finished. The repository is only read once an
  // action runs: this list is also built for a screen reader's actions.
  final container = ProviderScope.containerOf(context, listen: false);
  LibraryRepository repo() => container.read(libraryRepositoryProvider);

  void say(String message, {AppSnackTone tone = AppSnackTone.neutral}) {
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(messenger, message, tone: tone);
    }
  }

  void fail(Object e, StackTrace st, String fallback) {
    talker.handle(e, st);
    HapticFeedbackService.error();
    say(userFacingError(e, fallback: fallback), tone: AppSnackTone.danger);
  }

  if (folder.isSubscribed) {
    return [
      LibraryMenuAction(
        icon: Icons.link_off_rounded,
        label: 'Unsubscribe',
        destructive: true,
        onSelected: () async {
          try {
            await repo().unsubscribeFromBook(folder.id);
            container.invalidate(subscribedBooksProvider);
            container.invalidate(combinedLibraryFoldersProvider);
            HapticFeedbackService.success();
            say('Unsubscribed from "${folder.name}"');
          } catch (e, st) {
            fail(e, st, 'Could not unsubscribe. Please try again.');
          }
        },
      ),
    ];
  }

  final nonShareable = folder.parentId != null || folder.isFolder;
  void explainRootOnly() {
    HapticFeedbackService.error();
    say('only root-level folder can be shared with others');
  }

  final rename = LibraryMenuAction(
    icon: Icons.edit_rounded,
    label: 'Rename',
    onSelected: () async {
      if (!context.mounted) return;
      final next = await showRenameFolderDialog(
        context,
        currentName: folder.name,
      );
      final name = next?.trim();
      if (name == null || name.isEmpty || name == folder.name) return;
      try {
        await repo().updateFolder(
          folder.copyWith(name: name, updatedAt: DateTime.now()),
        );
        container.invalidate(libraryFoldersStreamProvider);
        HapticFeedbackService.success();
        say('Renamed to "$name"');
      } catch (e, st) {
        fail(e, st, 'Could not rename this item. Please try again.');
      }
    },
  );

  final delete = LibraryMenuAction(
    icon: Icons.delete_outline_rounded,
    label: 'Delete',
    destructive: true,
    onSelected: () async {
      if (!context.mounted) return;
      final confirmed = await showSmoothConfirmDialog(
        context: context,
        title: 'Delete ${folder.isFolder ? 'folder' : 'database'}?',
        message: folder.isFolder
            ? 'This permanently deletes the folder and every database inside it. This cannot be undone.'
            : 'This permanently deletes the database and every game inside it. This cannot be undone.',
        confirmText: 'Delete',
        isDangerous: true,
      );
      if (confirmed != true) return;
      try {
        await repo().deleteFolder(folder.id);
        container.invalidate(libraryFoldersStreamProvider);
        container.invalidate(folderAnalysisCountProvider);
        HapticFeedbackService.success();
        say('${folder.isFolder ? 'Folder' : 'Database'} deleted');
      } catch (e, st) {
        fail(e, st, 'Could not delete this item. Please try again.');
      }
    },
  );

  final shareToken = folder.shareToken;
  if (shareToken != null) {
    return [
      LibraryMenuAction(
        icon: Icons.copy_rounded,
        label: 'Copy Link',
        onSelected: nonShareable
            ? explainRootOnly
            : () {
                Clipboard.setData(
                  ClipboardData(
                    text: 'https://chessever.com/books/$shareToken',
                  ),
                );
                HapticFeedbackService.success();
                say('Link copied');
              },
      ),
      LibraryMenuAction(
        icon: Icons.link_off_rounded,
        label: 'Stop Sharing',
        onSelected: () async {
          try {
            await repo().revokeShareToken(folder.id);
            container.invalidate(libraryFoldersStreamProvider);
            HapticFeedbackService.success();
            say('Sharing stopped');
          } catch (e, st) {
            fail(e, st, 'Could not stop sharing. Please try again.');
          }
        },
      ),
      rename,
      delete,
    ];
  }

  return [
    LibraryMenuAction(
      icon: Icons.ios_share_rounded,
      label: 'Share',
      onSelected: nonShareable
          ? explainRootOnly
          : () async {
              try {
                final updated = await repo().generateShareToken(folder.id);
                container.invalidate(libraryFoldersStreamProvider);
                if (!context.mounted) return;
                final box = context.findRenderObject();
                final origin = box is RenderBox && box.hasSize
                    ? box.localToGlobal(Offset.zero) & box.size
                    : const Rect.fromLTWH(0, 0, 1, 1);
                await Share.share(
                  'https://chessever.com/books/${updated.shareToken}',
                  sharePositionOrigin: origin,
                );
              } catch (e, st) {
                fail(e, st, 'Could not share this. Please try again.');
              }
            },
    ),
    rename,
    delete,
  ];
}

/// The Library tab's "+" (new database, paste a PGN, pick a PGN file), run
/// from My Space without leaving it: a new database lands on the Library row
/// instead of opening, and its snack offers to open it. A PGN import still
/// shows its preview, the screen that import needs.
Future<void> spaceLibraryAdd(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showAddToLibrarySheet(context);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case AddToLibraryChoice.createDatabase:
      await _createDatabase(context, ref, messenger);
    case AddToLibraryChoice.importPgn:
      await _importFromClipboard(context);
    case AddToLibraryChoice.pickPgnFile:
      await _pickPgnFile(context);
  }
}

Future<void> _createDatabase(
  BuildContext context,
  WidgetRef ref,
  ScaffoldMessengerState? messenger,
) async {
  if (!ref.read(subscriptionProvider).isSubscribed) {
    final folders = await ref.read(libraryFoldersStreamProvider.future);
    final owned = folders
        .where((f) => !f.isSubscribed && f.id != kTwicBookId && f.isDatabase)
        .length;
    if (owned >= kFreeBookCreationLimit) {
      if (!context.mounted) return;
      await showPremiumPaywallSheet(context: context);
      return;
    }
  }
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final repository = ref.read(libraryRepositoryProvider);
  final data = await showCreateFolderDialog(context);
  if (data == null || data.name.isEmpty) return;
  try {
    final created = await repository.createFolder(
      name: data.name,
      parentId: data.parentId,
      nodeType: data.nodeType,
    );
    container.invalidate(libraryFoldersStreamProvider);
    container.invalidate(subscribedBooksProvider);
    HapticFeedbackService.success();
    if (messenger == null || !messenger.mounted) return;
    final kind = data.nodeType == LibraryFolder.nodeTypeFolder
        ? 'Folder'
        : 'Database';
    showAppSnackOn(
      messenger,
      '$kind "${data.name}" created',
      tone: AppSnackTone.success,
      actionLabel: 'Open',
      onAction: () {
        if (context.mounted) spaceOpenLibraryFolder(context, created);
      },
    );
  } catch (e, st) {
    talker.handle(e, st);
    HapticFeedbackService.error();
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        userFacingError(
          e,
          fallback: 'Could not create this item. Please try again.',
        ),
        tone: AppSnackTone.danger,
      );
    }
  }
}

Future<void> _importFromClipboard(BuildContext context) async {
  final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
  final text = clipboard?.text?.trim();
  if (!context.mounted) return;
  if (text == null || text.isEmpty) {
    showAppSnack(context, 'Clipboard is empty. Copy a PGN first.');
    return;
  }
  final parsed = parsePgnsToChessGames(text);
  if (parsed.isEmpty) {
    showAppSnack(
      context,
      'Clipboard does not contain a valid PGN',
      tone: AppSnackTone.danger,
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PgnImportPreviewScreen(
        games: parsed.map((e) => e.chessGame).toList(),
        sourceLabel: 'clipboard',
      ),
    ),
  );
}

Future<void> _pickPgnFile(BuildContext context) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pgn'],
      withData: false,
    );
  } catch (_) {
    // Some platforms reject custom extensions: any file will do.
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.any);
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      showAppSnack(
        context,
        userFacingError(
          e,
          fallback: 'Could not open the file picker. Please try again.',
        ),
        tone: AppSnackTone.danger,
      );
      return;
    }
  }
  final path = result?.files.singleOrNull?.path;
  if (path == null || path.isEmpty || !context.mounted) return;
  await PgnFileIntakeService.instance.ingestPgnFileFromContext(
    context: context,
    path: path,
    sourceLabel: 'device file',
  );
}
