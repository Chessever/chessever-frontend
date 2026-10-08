import 'dart:async';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<PrepAddResult?> showPrepSourcePicker(
  BuildContext context, {
  required PrepKind kind,
  PrepSource? only,
  Set<String> existingKeys = const {},
  bool attaching = false,
  String? lockedFideId,
}) => Navigator.of(context).push<PrepAddResult>(
  MaterialPageRoute(
    builder: (_) => _SourcePicker(
      kind: kind,
      only: only,
      existingKeys: existingKeys,
      attaching: attaching,
      lockedFideId: lockedFideId,
    ),
  ),
);

/// Every entry point creates the same person, without requiring a FIDE record.
class _SourcePicker extends ConsumerStatefulWidget {
  const _SourcePicker({
    required this.kind,
    required this.existingKeys,
    required this.attaching,
    this.only,
    this.lockedFideId,
  });
  final PrepKind kind;
  final PrepSource? only;
  final Set<String> existingKeys;
  final bool attaching;
  final String? lockedFideId;

  @override
  ConsumerState<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends ConsumerState<_SourcePicker> {
  late PrepSource _source = widget.only ?? PrepSource.chessever;
  final _query = TextEditingController();
  final _name = TextEditingController();
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
    _name.dispose();
    super.dispose();
  }

  void _changeSource(int index) {
    _debounce?.cancel();
    _generation++;
    _query.clear();
    _name.clear();
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
    if (account.source == PrepSource.chessever &&
        widget.existingKeys.any((key) => key.startsWith('chessever:'))) {
      return 'Detach the current ChessEver player first';
    }
    final owner = ref
        .read(prepProfilesProvider.notifier)
        .owning(account.source, account.externalId ?? account.username);
    if (owner != null && owner.kind != PrepKind.favorite) {
      return 'Already in ${owner.kind == PrepKind.mine ? 'My games' : owner.name}';
    }
    return null;
  }

  void _confirm() {
    final account = _selected;
    if (account == null || _unavailable(account) != null) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      PrepAddResult(
        _name.text.trim().isEmpty
            ? account.displayName ?? account.username
            : _name.text.trim(),
        [account],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(prepProfilesProvider);
    final colors = context.colors;
    final gutter = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);
    final database = _source == PrepSource.chessever;
    final selected = _selected;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        centerTitle: true,
        title: Text(
          widget.attaching
              ? 'Attach a source'
              : widget.kind == PrepKind.mine
              ? 'Add your profile'
              : 'Add an opponent',
          style: AppTypography.textMdBold,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.only == null)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: gutter,
                      vertical: 8.h,
                    ),
                    child: SegmentedSwitcher(
                      height: prepSegmentHeight(context),
                      options: PrepSource.playerSources
                          .map((s) => s.label)
                          .toList(),
                      initialSelection: PrepSource.playerSources.indexOf(
                        _source,
                      ),
                      currentSelection: PrepSource.playerSources.indexOf(
                        _source,
                      ),
                      backgroundColor: colors.popup,
                      selectedBackgroundColor: colors.popup,
                      onSelectionChanged: _changeSource,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 8.h),
                  child: TextField(
                    key: ValueKey('prep_source_query_${_source.name}'),
                    controller: _query,
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
                    decoration: prepInputDecoration(
                      context,
                      hint: database
                          ? 'Player name or FIDE ID'
                          : '${_source.label} username or profile URL',
                      prefix: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        child: PrepSourceMark(source: _source, size: 22.sp),
                      ),
                      suffix: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
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
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 12.h,
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: gutter,
                          vertical: 4.h,
                        ),
                        child: Text(
                          database
                              ? 'Search ChessEver, or start with an online account. You can attach the other sources later.'
                              : 'Anyone with an account can have a profile. A ChessEver database match is optional.',
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (_error != null ||
                          (!_busy &&
                              _query.text.trim().length >= 2 &&
                              _results.isEmpty))
                        Padding(
                          padding: EdgeInsets.all(gutter),
                          child: Column(
                            children: [
                              Text(
                                _error ??
                                    'No database match. Try their Lichess or Chess.com username.',
                                textAlign: TextAlign.center,
                                style: AppTypography.textSmRegular.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              if (_error == null &&
                                  !widget.attaching &&
                                  database)
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(
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
                      for (final account
                          in selected == null ? _results : [selected])
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
                          hideMissingRating: true,
                          detail:
                              _unavailable(account) ??
                              (database
                                  ? 'ChessEver database'
                                  : account.username),
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
                          onTap: () {
                            if (_unavailable(account) != null) return;
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _selected = account;
                              _name.text =
                                  account.displayName ?? account.username;
                            });
                          },
                        ),
                      if (selected != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            8.h,
                            gutter,
                            16.h,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _selected = null),
                                  child: const Text(
                                    'Choose a different player',
                                  ),
                                ),
                              ),
                              if (!widget.attaching &&
                                  widget.kind != PrepKind.mine) ...[
                                const PrepFieldLabel('Profile name'),
                                TextField(
                                  controller: _name,
                                  maxLength: 80,
                                  style: AppTypography.textMdMedium.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                  decoration: prepInputDecoration(
                                    context,
                                    hint: 'Player name',
                                  ),
                                ),
                                SizedBox(height: 12.h),
                              ],
                              FilledButton(
                                onPressed:
                                    saved.hasValue &&
                                        _unavailable(selected) == null
                                    ? _confirm
                                    : null,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: colors.textPrimary,
                                  foregroundColor: colors.textInverse,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.br),
                                  ),
                                ),
                                child: Text(
                                  widget.attaching
                                      ? 'Attach source'
                                      : 'Create profile',
                                  style: AppTypography.textSmBold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
