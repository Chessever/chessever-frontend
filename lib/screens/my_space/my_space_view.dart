import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What My Database says while it holds nothing.
const String kMyDatabaseEmptyText =
    'Save an event or a file to My Space and it is kept here. '
    'Long-press it and choose Add to My Space.';

/// Opens My Prep: the Library, exactly as its tab shows it, with a back
/// button where the tab keeps the avatar.
Future<void> openMyPrep(BuildContext context) {
  HapticFeedbackService.cardTap();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        body: const LibraryScreen(),
      ),
    ),
  );
}

/// The My Space tab, laid out like Today: the My Likes and My Prep tiles on
/// top (Today's Favorites and Countrymen pair), then My Database, everything
/// the user saved to My Space drawn with the app's own cards, and a tile to
/// build a Smart Event at the foot.
///
/// Works signed out too: the shortcuts provider keeps a device-local list
/// for guests.
class MySpaceView extends ConsumerWidget {
  const MySpaceView({super.key, this.scrollController});

  final ScrollController? scrollController;

  static const int _lead = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(spaceDatabaseProvider);
    final items = saved ?? const <SpaceShortcut>[];
    // Tiles and the header, the items (or one line saying what goes here,
    // or its skeleton while the list loads), then the Smart Event tile.
    final middle = items.isEmpty ? 1 : items.length;
    final count = _lead + middle + 1;

    return ListView.builder(
      key: const PageStorageKey<String>('my_space_list'),
      controller: scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      itemCount: count,
      // Rows keep their state as saved items come and go around them.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final at = items.indexWhere((s) => 'space_${s.key}' == key.value);
        return at < 0 ? null : _lead + at;
      },
      itemBuilder: (context, index) {
        if (index == 0) return const _MySpaceTiles();
        if (index == 1) return const HubSectionHeader(title: 'My Database');
        if (index == count - 1) {
          return Padding(
            padding: EdgeInsets.only(top: 8.sp),
            child: const _BuildSmartEventTile(),
          );
        }
        if (items.isEmpty) {
          return saved == null
              ? const _DatabaseSkeleton()
              : const _DatabaseEmpty();
        }
        final shortcut = items[index - _lead];
        return Padding(
          key: ValueKey<String>('space_${shortcut.key}'),
          padding: EdgeInsets.only(bottom: 12.sp),
          child: SpaceDatabaseItem(shortcut: shortcut),
        );
      },
    );
  }
}

class _MySpaceTiles extends StatelessWidget {
  const _MySpaceTiles();

  @override
  Widget build(BuildContext context) {
    return HubTileRow(
      left: HubTile(
        key: const ValueKey('my_space_likes_tile'),
        title: 'My Likes',
        ramp: false,
        artwork: const HubPixelArtwork(section: SpaceSection.likes),
        onTap: () {
          HapticFeedbackService.cardTap();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyLikesScreen()),
          );
        },
      ),
      right: HubTile(
        key: const ValueKey('my_space_prep_tile'),
        title: 'My Prep',
        ramp: false,
        artwork: const HubPixelArtwork(section: SpaceSection.openings),
        onTap: () => openMyPrep(context),
      ),
    );
  }
}

class _DatabaseEmpty extends StatelessWidget {
  const _DatabaseEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Text(
        kMyDatabaseEmptyText,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
          height: 20 / 14,
        ),
      ),
    );
  }
}

class _DatabaseSkeleton extends StatelessWidget {
  const _DatabaseSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: SkeletonWidget(
        ignoreContainers: true,
        child: Container(
          height: 80.sp,
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(8.br),
          ),
        ),
      ),
    );
  }
}

/// "+ Build smart event": the builder opens in place, and what it builds is
/// saved into My Database.
class _BuildSmartEventTile extends ConsumerWidget {
  const _BuildSmartEventTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HubTile(
      key: const ValueKey('my_space_build_smart_event'),
      title: 'Build smart event',
      titleIcon: Icons.add_rounded,
      caption: 'Openings you care about',
      ramp: false,
      artwork: const HubPixelArtwork(section: SpaceSection.smartEvents),
      onTap: () {
        HapticFeedbackService.buttonPress();
        showSpaceAddSheet(context, ref, SpaceSection.smartEvents);
      },
    );
  }
}
