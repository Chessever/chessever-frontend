import 'dart:async';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_options_dialog.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Asks for a player or username in a bottom sheet. With [only] the source
/// is already chosen; otherwise the sheet offers all three. With [askScope]
/// the sheet then pushes a page per chosen account for its clocks and period,
/// and hands the accounts back carrying them. [initial] accounts are already
/// chosen when the sheet opens, for a player whose accounts are known.
Future<PrepAddResult?> showPrepSourcePicker(
  BuildContext context, {
  required PrepKind kind,
  PrepSource? only,
  Set<String> existingKeys = const {},
  bool attaching = false,
  bool multiple = false,
  bool askScope = true,
  String? lockedFideId,
  List<PrepAccount> initial = const [],
}) => Navigator.of(context, rootNavigator: true).push(
  MotionSheetRoute<PrepAddResult>(
    barrierColor: context.colors.scrim,
    barrierLabel: 'Close',
    // Clear of the status bar, but down to the bottom edge.
    viewportPadding: EdgeInsets.only(
      top: MediaQuery.viewPaddingOf(context).top,
    ),
    builder: (_) => _PickerSheet(
      picker: (flow) => _SourcePicker(
        flow: flow,
        kind: kind,
        only: only,
        existingKeys: existingKeys,
        attaching: attaching,
        multiple: multiple,
        askScope: askScope,
        lockedFideId: lockedFideId,
        initial: initial,
      ),
    ),
  ),
);

/// What the sheet's pages share: the way out, and the download choices made
/// so far, which outlive the page that made them.
class _PickerFlow {
  _PickerFlow({required this.finish, required this.cancel});

  final ValueChanged<PrepAddResult> finish;
  final VoidCallback cancel;
  final scopes = <String, PrepDownloadPreferences>{};

  /// Ticks on every change to [scopes]. Each page sizes itself by all of
  /// them, the ones under the top page included.
  final scopesChanged = ValueNotifier(0);

  void finishWith(List<PrepAccount> accounts) =>
      finish(PrepAddResult.named(accounts));
}

Route<void> _pickerPage(WidgetBuilder builder) =>
    _PickerPageRoute(builder: builder);

/// How far a page travels sideways while it changes hands with the next.
const _pageShift = 24.0;

/// A page of the sheet, as tall as its content. The pages share one
/// see-through surface, so a step swaps their content in place: the
/// platform's page transition would slide their text across each other.
class _PickerPageRoute extends PagedSheetRoute<void> {
  _PickerPageRoute({required super.builder})
    : super(
        dragConfiguration: ChessSheetConfigs.commentEditor,
        scrollConfiguration: const SheetScrollConfiguration(),
        // Unused while the spring drives the step, but the route needs one.
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: _pageTransition,
      );

  static const _motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 350),
    snapToEnd: true,
  );

  @override
  Simulation createSimulation({required bool forward}) => _motion
      .createSimulation(start: controller!.value, end: forward ? 1.0 : 0.0);
}

/// The leaving page is gone before the arriving one shows, so their text
/// never overlaps on the shared surface. One opacity for both roles keeps a
/// page to a single layer.
Widget _pageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return AnimatedBuilder(
    animation: Listenable.merge([animation, secondaryAnimation]),
    child: child,
    builder: (context, child) {
      final arriving = animation.value;
      final leaving = secondaryAnimation.value;
      return Opacity(
        opacity: _ramp(arriving, 0.25, 0.85) * (1 - _ramp(leaving, 0, 0.3)),
        child: Transform.translate(
          offset: Offset(_pageShift * (1 - arriving - leaving), 0),
          child: child,
        ),
      );
    },
  );
}

double _ramp(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

/// A page's layout: its heading, its body, then its actions, in one scroll so
/// a short screen with the keyboard up still reaches every part of it.
class _PickerPage extends StatelessWidget {
  const _PickerPage({
    required this.header,
    required this.body,
    required this.actions,
    required this.actionsGap,
    this.dismissKeyboardOnDrag = false,
  });

  final Widget header;
  final List<Widget> body;
  final Widget actions;
  final double actionsGap;
  final bool dismissKeyboardOnDrag;

  @override
  Widget build(BuildContext context) {
    final inset = 20.sp;
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        keyboardDismissBehavior: dismissKeyboardOnDrag
            ? ScrollViewKeyboardDismissBehavior.onDrag
            : ScrollViewKeyboardDismissBehavior.manual,
        children: [
          header,
          ...body,
          Padding(
            padding: EdgeInsets.fromLTRB(inset, actionsGap, inset, inset),
            child: actions,
          ),
        ],
      ),
    );
  }
}

/// The sheet and the navigator its pages are pushed on, as the Library's
/// sheets set theirs up.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.picker});
  final Widget Function(_PickerFlow flow) picker;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _pages = GlobalKey<NavigatorState>();
  late final _flow = _PickerFlow(
    finish: (result) => Navigator.of(context).pop(result),
    cancel: () => Navigator.of(context).pop(),
  );

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<Object?>(
      // The system back gesture steps back a page before it leaves.
      onPopWithResult: (_) => _pages.currentState?.maybePop(),
      child: SheetKeyboardDismissible(
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
          // The page's spring carries the easing; a curve on top would ease
          // the sheet's height twice.
          transitionCurve: Curves.linear,
          navigator: Navigator(
            key: _pages,
            onGenerateInitialRoutes: (_, _) => [
              _pickerPage((_) => widget.picker(_flow)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every entry point creates the same person, without requiring a FIDE record.
class _SourcePicker extends ConsumerStatefulWidget {
  const _SourcePicker({
    required this.flow,
    required this.kind,
    required this.existingKeys,
    required this.attaching,
    required this.multiple,
    required this.askScope,
    this.only,
    this.lockedFideId,
    this.initial = const [],
  });
  final _PickerFlow flow;
  final PrepKind kind;
  final PrepSource? only;
  final Set<String> existingKeys;
  final bool attaching;
  final bool multiple;
  final bool askScope;
  final String? lockedFideId;
  final List<PrepAccount> initial;

  @override
  ConsumerState<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends ConsumerState<_SourcePicker> {
  late PrepSource _source = widget.only ?? PrepSource.chessever;
  final _query = TextEditingController();
  late final _pending = [...widget.initial];
  Timer? _debounce;
  int _generation = 0;
  bool _busy = false;
  String? _error;
  List<PrepAccount> _results = const [];
  PrepAccount? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changeSource(int index) {
    _debounce?.cancel();
    _generation++;
    _query.clear();
    setState(() {
      _source = PrepSource.playerSources[index];
      _results = const [];
      _selected = null;
      _error = null;
      _busy = false;
    });
  }

  void _changed(String text) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _selected = null;
      _results = const [];
      _error = null;
      _busy = text.trim().length >= 2;
    });
    if (!_busy) return;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(generation),
    );
  }

  Future<void> _search(int generation) async {
    final repo = ref.read(prepRepositoryProvider);
    try {
      final results = _source == PrepSource.chessever
          ? (await repo.searchPlayers(
              _query.text,
            )).map(PrepAccount.fromPlayer).toList()
          : [await repo.lookup(_source, _query.text)];
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _results = results;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = error is PrepException
            ? error.message
            : 'Could not search. Check your connection and retry.';
      });
    }
  }

  String? _unavailable(PrepAccount account) {
    if (account.source == PrepSource.chessever &&
        widget.lockedFideId != null &&
        widget.lockedFideId != account.fideId) {
      return 'Choose FIDE ${widget.lockedFideId} for this profile';
    }
    if (widget.existingKeys.contains(account.key)) return 'Already attached';
    if (_pending.any((a) => a.key == account.key)) return 'Already added';
    if (account.source == PrepSource.chessever &&
        widget.existingKeys.any((key) => key.startsWith('chessever:'))) {
      return 'Detach the current ChessEver player first';
    }
    if (account.source == PrepSource.chessever &&
        _pending.any((a) => a.source == PrepSource.chessever)) {
      return 'A ChessEver player is already added';
    }
    final owner = ref
        .read(prepProfilesProvider.notifier)
        .owning(account.source, account.externalId ?? account.username);
    if (owner != null && owner.kind != PrepKind.favorite) {
      return 'Already in ${owner.kind == PrepKind.mine ? 'My games' : owner.name}';
    }
    return null;
  }

  void _select(PrepAccount account) {
    if (_unavailable(account) != null) return;
    FocusScope.of(context).unfocus();
    if (widget.multiple) {
      _debounce?.cancel();
      _generation++;
      _query.clear();
      setState(() {
        _pending.add(account);
        _results = const [];
        _error = null;
        _busy = false;
      });
    } else {
      // Tapping the chosen row again releases it back to the results.
      setState(
        () => _selected = _selected?.key == account.key ? null : account,
      );
    }
  }

  void _confirmPending() {
    if (_pending.isEmpty) return;
    _chosen(List.unmodifiable(_pending));
  }

  void _confirm() {
    final account = _selected;
    if (account == null || _unavailable(account) != null) return;
    _chosen([account]);
  }

  void _chosen(List<PrepAccount> accounts) {
    FocusScope.of(context).unfocus();
    if (widget.askScope) {
      // The picker stays under the pages, its accounts intact.
      Navigator.of(context).push(
        _pickerPage(
          (_) => _ScopePage(flow: widget.flow, accounts: accounts, index: 0),
        ),
      );
    } else {
      widget.flow.finishWith(accounts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(prepProfilesProvider);
    final colors = context.colors;
    final inset = 20.sp;
    final database = _source == PrepSource.chessever;
    final selected = _selected;
    final noMatch =
        _error != null ||
        (!_busy && _query.text.trim().length >= 2 && _results.isEmpty);
    final queued = widget.multiple && _pending.isNotEmpty;
    final title = widget.kind == PrepKind.mine
        ? 'Attach your usernames'
        : widget.attaching
        ? widget.multiple
              ? 'Add accounts'
              : 'Attach a source'
        : widget.kind == PrepKind.favorite
        ? 'Add a favorite'
        : 'Add an opponent';
    return _PickerPage(
      dismissKeyboardOnDrag: true,
      actionsGap: 16.h,
      header: Padding(
        padding: EdgeInsets.fromLTRB(inset, inset, inset, 0),
        child: Row(
          children: [
            PrepSourceMark(source: _source, size: 24.sp),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textLgBold.copyWith(
                      color: colors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (widget.only != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      _source.label,
                      style: AppTypography.textXsRegular.copyWith(
                        color: colors.textSecondary,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: [
        if (widget.only == null)
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 16.h, inset, 0),
            // Filled-ink chips, as in the prep filter dialogs: the
            // text-only tab strip left the selection unreadable here.
            // Equal widths keep all three on one row at dialog width.
            child: Row(
              children: [
                for (final (index, source)
                    in PrepSource.playerSources.indexed) ...[
                  if (index > 0) SizedBox(width: 6.w),
                  Expanded(
                    child: _SourceChip(
                      label: source.label,
                      selected: source == _source,
                      onTap: () {
                        if (source != _source) _changeSource(index);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 16.h, inset, 0),
          child: TextField(
            // One field across every source: a per-source key remounts
            // it, dropping focus and bouncing the keyboard on tab switch.
            key: const ValueKey('prep_source_query'),
            controller: _query,
            // Accounts already chosen are reviewed first; the keyboard
            // would cover them.
            autofocus: widget.initial.isEmpty,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (_) {
              _debounce?.cancel();
              if (_query.text.trim().length >= 2) {
                setState(() => _busy = true);
                unawaited(_search(++_generation));
              }
            },
            style: AppTypography.textMdMedium.copyWith(
              color: colors.textPrimary,
            ),
            cursorColor: colors.accentText,
            decoration: prepInputDecoration(
              context,
              hint: database
                  ? 'Player name or FIDE ID'
                  : 'Username or profile URL',
              suffix: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _query.clear();
                        _changed('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (noMatch)
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 0),
                  child: Column(
                    children: [
                      Text(
                        _error ??
                            (widget.kind == PrepKind.mine
                                ? 'No database match. Try your Lichess or Chess.com username.'
                                : 'No database match. Try their Lichess or Chess.com username.'),
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (_error == null &&
                          !widget.attaching &&
                          widget.kind != PrepKind.mine &&
                          database)
                        TextButton(
                          onPressed: () => widget.flow.finish(
                            PrepAddResult(_query.text.trim(), const []),
                          ),
                          child: const Text('Create a profile by name'),
                        ),
                      if (_error != null)
                        TextButton(
                          onPressed: () {
                            setState(() => _busy = true);
                            unawaited(_search(++_generation));
                          },
                          child: const Text('Retry search'),
                        ),
                    ],
                  ),
                ),
              for (final account in selected == null ? _results : [selected])
                FigmaPlayerCard(
                  key: ValueKey(account.key),
                  player: PlayerStandingModel(
                    name: account.displayName ?? account.username,
                    countryCode: account.country ?? '',
                    title: account.title,
                    score: account.bestRating ?? 0,
                    scoreChange: 0,
                    matchScore: null,
                    fideId: int.tryParse(account.fideId ?? ''),
                  ),
                  rank: null,
                  showRank: false,
                  reserveRankSpace: false,
                  hideMissingRating: true,
                  detail:
                      _unavailable(account) ??
                      (account.displayName != null &&
                              account.displayName != account.username
                          ? account.username
                          : null),
                  avatar: PrepAvatar(
                    name: account.displayName ?? account.username,
                    size: 56.w,
                    fideId: account.fideId,
                    photoUrl: account.avatarUrl,
                    title: account.title,
                  ),
                  trailing: _unavailable(account) != null
                      ? null
                      : Icon(
                          selected?.key == account.key
                              ? Icons.check_circle_rounded
                              : Icons.add_rounded,
                          color: colors.textPrimary,
                          size: 22.ic,
                        ),
                  onTap: () => _select(account),
                ),
              for (final account in _pending)
                Padding(
                  key: ValueKey('prep_pending_${account.key}'),
                  padding: EdgeInsets.fromLTRB(12.w, 4.h, 0, 4.h),
                  child: Row(
                    children: [
                      PrepSourceMark(source: account.source, size: 22.sp),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          account.source.online
                              ? account.username
                              : account.displayName ?? account.username,
                          semanticsLabel:
                              '${account.source.online ? account.username : account.displayName ?? account.username} on ${account.source.label}',
                          style: AppTypography.textSmMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${account.username}',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () =>
                            setState(() => _pending.remove(account)),
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.iconSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      actions: Row(
        children: [
          Expanded(
            child: TextButton(
              key: const ValueKey('prep_source_cancel'),
              onPressed: widget.flow.cancel,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.br),
                ),
              ),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          if (queued || selected != null) ...[
            SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: queued ? const ValueKey('prep_attach_accounts') : null,
                onPressed: !saved.hasValue
                    ? null
                    : queued
                    ? _confirmPending
                    : _unavailable(selected!) == null
                    ? _confirm
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.textInverse,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                ),
                child: Text(
                  queued && (widget.attaching || widget.kind == PrepKind.mine)
                      ? _pending.length == 1
                            ? 'Attach account'
                            : 'Attach ${_pending.length} accounts'
                      : widget.attaching
                      ? 'Attach source'
                      : 'Create profile',
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmBold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One account's clocks and period, a page of the sheet per account.
class _ScopePage extends StatefulWidget {
  const _ScopePage({
    required this.flow,
    required this.accounts,
    required this.index,
  });
  final _PickerFlow flow;
  final List<PrepAccount> accounts;
  final int index;

  @override
  State<_ScopePage> createState() => _ScopePageState();
}

class _ScopePageState extends State<_ScopePage> {
  PrepAccount get _account => widget.accounts[widget.index];
  bool get _last => widget.index == widget.accounts.length - 1;

  PrepDownloadPreferences _scopeOf(PrepAccount account) =>
      widget.flow.scopes[account.key] ??
      PrepDownloadPreferences.initialFor(account.source);

  @override
  void initState() {
    super.initState();
    widget.flow.scopesChanged.addListener(_scopesChanged);
  }

  @override
  void dispose() {
    widget.flow.scopesChanged.removeListener(_scopesChanged);
    super.dispose();
  }

  void _scopesChanged() => setState(() {});

  /// The first page steps back to the picker.
  void _back() {
    HapticFeedbackService.selection();
    Navigator.of(context).pop();
  }

  void _advance() {
    if (!_last) {
      HapticFeedbackService.selection();
      Navigator.of(context).push(
        _pickerPage(
          (_) => _ScopePage(
            flow: widget.flow,
            accounts: widget.accounts,
            index: widget.index + 1,
          ),
        ),
      );
      return;
    }
    HapticFeedbackService.medium();
    widget.flow.finishWith([
      for (final account in widget.accounts)
        account.copyWith(preferences: _scopeOf(account)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inset = 20.sp;
    final account = _account;
    final scope = _scopeOf(account);
    final total = widget.accounts.length;
    final name = account.source.online
        ? account.username
        : account.displayName ?? account.username;
    return _PickerPage(
      actionsGap: 10.h,
      header: Padding(
        // The arrow's glyph, not its 44pt target, lines up with the fields.
        padding: EdgeInsets.fromLTRB(inset - 12, inset - 4, inset, 0),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('prep_scope_back'),
              tooltip: 'Back',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _back,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: colors.textPrimary,
                size: 20.ic,
              ),
            ),
            SizedBox(width: 4.w),
            PrepSourceMark(source: account.source, size: 24.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Download games',
                    style: AppTypography.textLgBold.copyWith(
                      color: colors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '$name on ${account.source.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsRegular.copyWith(
                      color: colors.textSecondary,
                      height: 16 / 12,
                    ),
                  ),
                ],
              ),
            ),
            if (total > 1) ...[
              SizedBox(width: 12.w),
              Text(
                '${widget.index + 1}/$total',
                semanticsLabel: 'Source ${widget.index + 1} of $total',
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
      body: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 20.h, inset, 0),
          // Every account's fields are laid out and the one in turn shown,
          // so each page is as tall as the tallest and a step between them
          // leaves the sheet where it is.
          child: IndexedStack(
            index: widget.index,
            children: [
              for (final other in widget.accounts)
                PrepScopeFields(
                  key: ValueKey('prep_scope_${other.key}'),
                  sources: [other.source],
                  value: _scopeOf(other),
                  onChanged: (value) {
                    widget.flow.scopes[other.key] = value;
                    widget.flow.scopesChanged.value++;
                  },
                ),
            ],
          ),
        ),
      ],
      actions: PrepDialogActions(
        confirmLabel: _last ? 'Download' : 'Next',
        onConfirm: scope.validationError == null ? _advance : null,
        onCancel: widget.flow.cancel,
      ),
    );
  }
}

/// [PrepChip]'s look, stretched to fill an equal share of the row.
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: TappableScale(
        scaleDown: 0.97,
        onTap: () {
          HapticFeedbackService.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? colors.textPrimary
                : colors.textPrimary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10.br),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textSmMedium.copyWith(
              color: selected ? colors.textInverse : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
