import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An add sheet open over one My Space row, and what it has added so far.
@immutable
class SpaceSheetSession {
  const SpaceSheetSession({required this.section, this.added = const {}});

  final SpaceSection section;

  /// Keys pinned from the sheet. The row holds them back while the sheet is
  /// up and lets them spring in once it closes, where they can be seen.
  final Set<String> added;

  SpaceSheetSession withAdded(String key) =>
      SpaceSheetSession(section: section, added: {...added, key});

  SpaceSheetSession withoutAdded(String key) =>
      SpaceSheetSession(section: section, added: {...added}..remove(key));
}

final spaceSheetSessionProvider = StateProvider<SpaceSheetSession?>(
  (ref) => null,
);
