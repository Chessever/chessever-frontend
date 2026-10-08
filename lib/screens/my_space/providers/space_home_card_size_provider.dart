import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/my_space/providers/space_home_layout_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SpaceHomeCardSize { small, fullRow }

const kSpaceHomeCardSizesKey = 'my_space_home_card_sizes_v1';

/// Size belongs to the card, independent of where a drag places it. Existing
/// arrangements retain their sizes until the reader explicitly changes one.
SpaceHomeCardSize spaceHomeCardSizeFor(
  String key,
  Map<String, SpaceHomeCardSize> sizes,
) =>
    sizes[key] ??
    (key == kSpaceHomeMyPrep || key == kSpaceHomeLibrary
        ? SpaceHomeCardSize.small
        : SpaceHomeCardSize.fullRow);

class SpaceHomeCardSizes extends Notifier<Map<String, SpaceHomeCardSize>> {
  @override
  Map<String, SpaceHomeCardSize> build() {
    final raw = SharedPreferencesService.instance.prefsOrNull?.getString(
      kSpaceHomeCardSizesKey,
    );
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String)
            for (final size in SpaceHomeCardSize.values)
              if (entry.value == size.name) entry.key as String: size,
      };
    } catch (_) {
      return const {};
    }
  }

  void setSize(String key, SpaceHomeCardSize size) {
    if (spaceHomeCardSizeFor(key, state) == size) return;
    state = {...state, key: size};
    final prefs = SharedPreferencesService.instance.prefsOrNull;
    if (prefs == null) return;
    unawaited(
      prefs.setString(
        kSpaceHomeCardSizesKey,
        jsonEncode({
          for (final entry in state.entries) entry.key: entry.value.name,
        }),
      ),
    );
  }

  void toggle(String key) => setSize(
    key,
    spaceHomeCardSizeFor(key, state) == SpaceHomeCardSize.small
        ? SpaceHomeCardSize.fullRow
        : SpaceHomeCardSize.small,
  );
}

final spaceHomeCardSizesProvider =
    NotifierProvider<SpaceHomeCardSizes, Map<String, SpaceHomeCardSize>>(
      SpaceHomeCardSizes.new,
    );
