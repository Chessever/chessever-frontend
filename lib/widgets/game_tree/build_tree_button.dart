import 'dart:async';
import 'dart:io';

import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/game_tree_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Something whose games can become an opening tree: a Library database,
/// a collection, a My Prep player or one of their accounts.
abstract class GameTreeTarget {
  const GameTreeTarget();

  /// Stable across sessions; names the index on disk.
  String get scopeId;

  /// What the explorer is titled.
  String get title;

  /// Whether games have a prepared player whose side the tree tracks.
  bool get playerScope => false;
  String? get country => null;
  String? get playerTitle => null;

  /// Building a tree is Premium; a My Prep player's tree is not gated
  /// again, since adding the player already was and its downloaded games
  /// stay readable, as the Openings tab always allowed.
  bool get requiresPremium => true;

  /// Whether an index built earlier still matches the games.
  Future<bool> isCurrent(GameTreeStore store);

  /// Builds or updates the index, reporting progress as it goes. Throws
  /// [GameTreeCanceled] when stopped.
  Future<GameTreeStore> build(void Function(GameTreeStatus status) report);
}

/// A target whose games are fetched (a cloud database, a collection): its
/// PGN is written to the tree's own file, then indexed.
abstract class RemoteGameTreeTarget extends GameTreeTarget {
  const RemoteGameTreeTarget();

  /// Changes whenever the games do; a game count serves.
  Future<String> revision();

  /// Writes every game through [add], reporting how many so far of
  /// [total]. Stops early when [canceled] says so.
  Future<void> collect(
    void Function(String pgn) add,
    void Function(int done, int? total) progress,
    bool Function() canceled,
  );

  @override
  Future<bool> isCurrent(GameTreeStore store) async =>
      store.revision != null && store.revision == await revision();

  @override
  Future<GameTreeStore> build(
    void Function(GameTreeStatus status) report,
  ) async {
    report(
      const GameTreeStatus(
        phase: GameTreePhase.fetching,
        fraction: 0,
        message: 'Downloading games',
      ),
    );
    final revision = await this.revision();
    final path = await GameTreeService.pgnPath(scopeId);
    final writer = await GameTreePgnWriter.open(path);
    try {
      await collect(
        writer.add,
        (done, total) => report(
          GameTreeStatus(
            phase: GameTreePhase.fetching,
            fraction: total == null || total == 0 ? null : 0.5 * done / total,
            message: 'Downloading games',
          ),
        ),
        () => GameTreeService.cancelRequested(scopeId),
      );
      if (GameTreeService.cancelRequested(scopeId)) {
        throw const GameTreeCanceled();
      }
      await writer.commit();
    } catch (_) {
      await writer.discard();
      rethrow;
    }
    return GameTreeService.ensure(
      scopeId: scopeId,
      sources: [GameTreeSourceFile(path: path, kind: 'pgn')],
      revision: revision,
      playerScope: playerScope,
      onProgress: (fraction) => report(
        GameTreeStatus(
          phase: GameTreePhase.indexing,
          fraction: 0.5 + fraction / 2,
          message: 'Indexing games',
        ),
      ),
    );
  }
}

/// Whether [scopeId] has an index on this device.
final gameTreeBuiltProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, scopeId) async =>
      File(await GameTreeService.databasePath(scopeId)).exists(),
);

/// Opens [target]'s tree in the explorer, building it first when needed.
/// Tapping again while it builds stops the build, as on desktop.
Future<void> openOrBuildGameTree(
  BuildContext context,
  WidgetRef ref,
  GameTreeTarget target, {
  GamebasePlayerColor? color,
  TimeControl? timeControl,
}) async {
  final scope = target.scopeId;
  final statusNotifier = ref.read(gameTreeStatusProvider.notifier);
  final current = ref.read(gameTreeStatusProvider)[scope];
  if (current?.busy ?? false) {
    HapticFeedbackService.buttonPress();
    await GameTreeService.cancel(scope);
    return;
  }
  HapticFeedbackService.buttonPress();
  if (target.requiresPremium && !await ensureGameTreeAccess(context)) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);

  void open() {
    if (!context.mounted) return;
    unawaited(
      openGameTreeExplorer(
        context,
        scopeId: scope,
        title: target.title,
        country: target.country,
        playerTitle: target.playerTitle,
        color: color,
        timeControl: timeControl,
      ),
    );
  }

  try {
    final existing = await GameTreeService.existing(
      scope,
      playerScope: target.playerScope,
    );
    if (existing != null &&
        existing.isCurrentVersion &&
        existing.gameCount > 0 &&
        await target.isCurrent(existing)) {
      open();
      return;
    }
    statusNotifier.set(
      scope,
      const GameTreeStatus(phase: GameTreePhase.fetching, fraction: 0),
    );
    final store = await target.build(
      (status) => statusNotifier.set(scope, status),
    );
    statusNotifier.clear(scope);
    container.invalidate(gameTreeBuiltProvider(scope));
    if (store.gameCount == 0) {
      if (messenger != null) {
        showAppSnackOn(messenger, 'There are no games to build a tree from.');
      }
      return;
    }
    HapticFeedbackService.success();
    open();
  } on GameTreeCanceled {
    statusNotifier.clear(scope);
    container.invalidate(gameTreeBuiltProvider(scope));
    if (messenger != null) showAppSnackOn(messenger, 'Tree build stopped.');
  } catch (error) {
    debugPrint('[GameTree] build failed for $scope: $error');
    statusNotifier.set(
      scope,
      GameTreeStatus(phase: GameTreePhase.failed, error: '$error'),
    );
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Could not build the tree. Check your connection and try again.',
        tone: AppSnackTone.danger,
      );
    }
  }
}

/// The header control every games view carries at its top-right: "Build
/// Tree" until a tree exists, "Tree" after, and its progress while it
/// builds. The labels are desktop's, so the two apps read the same.
class BuildTreeButton extends ConsumerWidget {
  const BuildTreeButton({
    super.key,
    required this.target,
    this.compact,
    this.color,
    this.timeControl,
  });

  final GameTreeTarget target;
  final GamebasePlayerColor? color;
  final TimeControl? timeControl;

  /// The glyph alone, for headers whose actions are already a row of
  /// icons. The label moves to the tooltip and the screen reader. Null
  /// picks the glyph only on a narrow phone, where the labelled pill would
  /// squeeze the title.
  final bool? compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(
      gameTreeStatusProvider.select((s) => s[target.scopeId]),
    );
    final built =
        ref.watch(gameTreeBuiltProvider(target.scopeId)).valueOrNull ?? false;
    final busy = status?.busy ?? false;
    final failed = status?.phase == GameTreePhase.failed;
    final ready = built && !busy && !failed;
    final label = busy
        ? 'Tree ${status?.percent ?? 0}%'
        : failed
        ? 'Retry Tree'
        : built
        ? 'Tree'
        : 'Build Tree';
    final semantics = busy
        ? 'Building the opening tree, ${status?.percent ?? 0} percent. '
              'Double tap to stop.'
        : ready
        ? 'Open the opening tree'
        : 'Build an opening tree from these games';

    if (compact ?? MediaQuery.sizeOf(context).width < 390) {
      return Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: TappableScale(
            scaleDown: 0.95,
            onTap: () => openOrBuildGameTree(
              context,
              ref,
              target,
              color: color,
              timeControl: timeControl,
            ),
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: AppBarIconSurface(
                  child: busy
                      ? SizedBox.square(
                          dimension: 20.sp,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: status?.fraction,
                            color: colors.textPrimary,
                            backgroundColor: colors.textPrimary.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        )
                      : Icon(
                          failed
                              ? Icons.restart_alt_rounded
                              : ready
                              ? Icons.account_tree_rounded
                              : Icons.account_tree_outlined,
                          size: 20.sp,
                          color: colors.textPrimary,
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final fg = ready ? colors.textInverse : colors.textPrimary;
    final bg = ready
        ? colors.textPrimary
        : colors.textPrimary.withValues(alpha: 0.08);

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: TappableScale(
        scaleDown: 0.95,
        onTap: () => openOrBuildGameTree(
          context,
          ref,
          target,
          color: color,
          timeControl: timeControl,
        ),
        child: ConstrainedBox(
          // A 44dp target around a 32dp pill.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32.h,
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16.h),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 16.sp,
                    child: busy
                        ? CircularProgressIndicator(
                            strokeWidth: 2,
                            value: status?.fraction,
                            color: fg,
                            backgroundColor: fg.withValues(alpha: 0.15),
                          )
                        : Icon(
                            failed
                                ? Icons.restart_alt_rounded
                                : Icons.account_tree_rounded,
                            size: 16.sp,
                            color: fg,
                          ),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    label,
                    maxLines: 1,
                    style: AppTypography.textXsBold.copyWith(
                      color: fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
