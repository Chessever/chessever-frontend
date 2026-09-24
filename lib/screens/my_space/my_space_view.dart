import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_row.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The My Space tab: one row per [SpaceSection], in the enum's order. Every
/// row is always shown: an empty one is its door alone, stretched across the
/// page, so the first visit reads as a set of places to fill rather than a
/// blank. The Shortcuts row is the exception: it only appears once it holds
/// something.
///
/// Nothing starts empty, though. Library and My Likes mirror their tabs live,
/// Openings and Smart Events arrive with defaults already pinned, and the
/// other rows carry what follows the user (followed players, live events,
/// today's most liked games) until they pin their own.
///
/// Until the space has held [kSpaceFirstRunHintRetireAt] things, one quiet
/// line on top says how to fill it; after that it never shows again on this
/// device.
///
/// Works signed out too: the shortcuts provider keeps a device-local list for
/// guests.
class MySpaceView extends ConsumerWidget {
  const MySpaceView({super.key, this.scrollController});

  final ScrollController? scrollController;

  static List<SpaceSection> visibleSections(
    Map<SpaceSection, List<SpaceShortcut>> bySection,
  ) => [
    for (final section in SpaceSection.values)
      if (section != SpaceSection.links ||
          (bySection[section]?.isNotEmpty ?? false))
        section,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(spaceShortcutsProvider.select((a) => a.hasValue));
    final bySection = ref.watch(spaceShortcutsBySectionProvider);
    final sections = visibleSections(bySection);
    final count = ref.watch(
      spaceShortcutsProvider.select((a) => a.valueOrNull?.length ?? 0),
    );
    final hintRetired = ref.watch(spaceFirstRunHintRetiredProvider);
    final showHint =
        ready && !hintRetired && count < kSpaceFirstRunHintRetireAt;
    final lead = showHint ? 1 : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ListView.builder(
          controller: scrollController,
          scrollCacheExtent: kListScrollCacheExtent,
          padding: EdgeInsets.only(bottom: 24.w),
          itemCount: sections.length + lead,
          // Rows keep their state when the first-run line above them retires.
          findChildIndexCallback: (key) {
            if (key is! ValueKey<SpaceSection>) return null;
            final at = sections.indexOf(key.value);
            return at < 0 ? null : at + lead;
          },
          itemBuilder: (context, i) {
            if (i < lead) {
              return const SpaceFirstRunHint(key: ValueKey('__space_hint__'));
            }
            final index = i - lead;
            final section = sections[index];
            return SpaceSectionRow(
              key: ValueKey(section),
              section: section,
              items: bySection[section] ?? const <SpaceShortcut>[],
              availableWidth: width,
              topGap: index == 0 ? 6.w : 28.w,
              ready: ready,
            );
          },
        );
      },
    );
  }
}
