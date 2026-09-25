import 'dart:async';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The first-run line at the top of My Space. Names both ways in: the `+` on
/// each door below, and a long-press anywhere else in the app.
const String kSpaceFirstRunHint =
    'Tap a + to add, or hold anything in ChessEver.';

/// Once My Space holds this many things, the line retires for good.
const int kSpaceFirstRunHintRetireAt = 2;

/// Device-local memory of whether the first-run line has retired.
///
/// Read synchronously from the preferences loaded at startup, so My Space never
/// paints the line for a frame and then drops it.
class SpaceFirstRunHintStore {
  const SpaceFirstRunHintStore();

  static const _key = 'my_space_first_run_hint_retired.v1';

  bool readRetired() =>
      SharedPreferencesService.instance.prefsOrNull?.getBool(_key) ?? false;

  Future<void> writeRetired() async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setBool(_key, true);
    } catch (e) {
      debugPrint('[MySpace] first-run hint flag not saved: $e');
    }
  }
}

final spaceFirstRunHintStoreProvider = Provider<SpaceFirstRunHintStore>(
  (ref) => const SpaceFirstRunHintStore(),
);

/// True once the first-run line has retired on this device: My Space has held
/// [kSpaceFirstRunHintRetireAt] things at some point. It never comes back, even
/// if those things are removed again.
final spaceFirstRunHintRetiredProvider =
    NotifierProvider<SpaceFirstRunHintNotifier, bool>(
      SpaceFirstRunHintNotifier.new,
    );

class SpaceFirstRunHintNotifier extends Notifier<bool> {
  static bool _reached(int? count) =>
      count != null && count >= kSpaceFirstRunHintRetireAt;

  @override
  bool build() {
    final store = ref.watch(spaceFirstRunHintStoreProvider);
    ref.listen<int?>(
      spaceShortcutsProvider.select((a) => a.valueOrNull?.length),
      (_, count) {
        if (state || !_reached(count)) return;
        state = true;
        unawaited(store.writeRetired());
      },
    );
    if (store.readRetired()) return true;
    if (_reached(ref.read(spaceShortcutsProvider).valueOrNull?.length)) {
      unawaited(store.writeRetired());
      return true;
    }
    return false;
  }
}

/// One quiet line teaching how My Space fills up. Sits above the rows; the
/// doors below stay as they are.
class SpaceFirstRunHint extends StatelessWidget {
  const SpaceFirstRunHint({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = SpaceMetrics.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 10.w, gutter, 8.w),
      child: Text(
        kSpaceFirstRunHint,
        style: spaceText(
          context,
          size: 13,
          line: 18,
          weight: FontWeight.w400,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}
