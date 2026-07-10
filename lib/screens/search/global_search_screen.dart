import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/search/providers/recent_search_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/liquid_glass/glass_floating_segments.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Dedicated full-screen search — Apple Music style liquid glass experience.
///
/// - Top: **Players | Events** glass segment island
/// - Body: recently searched (empty query) or live results
/// - Bottom: floating [GlassSearchBar] + cancel, above the keyboard
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  static Route<void> route({String initialQuery = ''}) {
    return MaterialPageRoute<void>(
      builder: (_) => GlobalSearchScreen(initialQuery: initialQuery),
      fullscreenDialog: true,
    );
  }

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

enum _SearchTab { players, events }

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  String _query = '';
  _SearchTab _tab = _SearchTab.players;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
    _query = widget.initialQuery.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      if (_query.isNotEmpty) {
        ref.read(recentSearchesProvider.notifier).add(_query);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    final next = raw.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _query = next);
      if (next.isNotEmpty) {
        ref.read(recentSearchesProvider.notifier).add(next);
      }
    });
  }

  void _applyRecent(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() => _query = q.trim());
    ref.read(recentSearchesProvider.notifier).add(q);
    _focusNode.requestFocus();
  }

  void _close() {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).maybePop();
  }

  void _openPlayer(SearchPlayer player) {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title: player.title,
              federation: player.fed,
              rating: player.rating,
            ),
      ),
    );
  }

  Future<void> _openEvent(GroupEventCardModel event) async {
    HapticFeedbackService.buttonPress();
    await ref
        .read(tournamentNavigationProvider)
        .openTournament(
          context: context,
          id: event.id,
          category: GroupEventCategory.search,
        );
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentSearchesProvider);
    final pad = ResponsiveHelper.adaptive(phone: 12.0, tablet: 24.0);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            GlassIslandStack(
              gap: 8,
              children: [
                GlassFloatingSegments(
                  options: const ['Players', 'Events'],
                  selectedIndex: _tab == _SearchTab.players ? 0 : 1,
                  expanded: true,
                  horizontalPadding: pad,
                  onSelected: (i) {
                    setState(() {
                      _tab = i == 0 ? _SearchTab.players : _SearchTab.events;
                    });
                  },
                ),
              ],
            ),
            Expanded(
              child:
                  _query.isEmpty
                      ? _RecentSearchesBody(
                        recent: recent,
                        onSelect: _applyRecent,
                        onClear:
                            () => ref.read(recentSearchesProvider.notifier).clear(),
                        onRemove:
                            (q) =>
                                ref.read(recentSearchesProvider.notifier).remove(q),
                        tab: _tab,
                      )
                      : _SearchResultsBody(
                        query: _query,
                        tab: _tab,
                        onPlayer: _openPlayer,
                        onEvent: _openEvent,
                      ),
            ),
            // Floating glass search dock (Apple Music: field + dismiss).
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                8,
                pad,
                12 + (keyboard > 0 ? keyboard : MediaQuery.paddingOf(context).bottom),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GlassSearchBar(
                      controller: _controller,
                      focusNode: _focusNode,
                      placeholder:
                          _tab == _SearchTab.players
                              ? 'Search players'
                              : 'Search events',
                      onChanged: _onQueryChanged,
                      onSubmitted: (v) {
                        final q = v.trim();
                        if (q.isEmpty) return;
                        setState(() => _query = q);
                        ref.read(recentSearchesProvider.notifier).add(q);
                      },
                      autofocus: false,
                      useOwnLayer: true,
                      height: 50,
                      showsCancelButton: false,
                      searchIconColor: context.colors.iconSecondary,
                      clearIconColor: context.colors.iconSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassIconButton(
                    icon: Icon(
                      CupertinoIcons.xmark,
                      color: context.colors.iconPrimary,
                    ),
                    onPressed: _close,
                    size: 50,
                    iconSize: 20,
                    useOwnLayer: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSearchesBody extends StatelessWidget {
  const _RecentSearchesBody({
    required this.recent,
    required this.onSelect,
    required this.onClear,
    required this.onRemove,
    required this.tab,
  });

  final List<String> recent;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;
  final ValueChanged<String> onRemove;
  final _SearchTab tab;

  @override
  Widget build(BuildContext context) {
    final pad = ResponsiveHelper.adaptive(phone: 16.0, tablet: 24.0);

    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.search,
                size: 48,
                color: context.colors.iconSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                tab == _SearchTab.players
                    ? 'Search players'
                    : 'Search events',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Find ${tab == _SearchTab.players ? 'players by name' : 'tournaments and events'}',
                textAlign: TextAlign.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recently Searched',
                style: AppTypography.textMdBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Clear',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.brand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final q in recent) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(q),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.clock,
                      size: 18,
                      color: context.colors.iconSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        q,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textMdRegular.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onRemove(q),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: context.colors.iconSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: context.colors.divider.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
  }
}

class _SearchResultsBody extends ConsumerWidget {
  const _SearchResultsBody({
    required this.query,
    required this.tab,
    required this.onPlayer,
    required this.onEvent,
  });

  final String query;
  final _SearchTab tab;
  final ValueChanged<SearchPlayer> onPlayer;
  final ValueChanged<GroupEventCardModel> onEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supabaseCombinedSearchProvider(query));
    final pad = ResponsiveHelper.adaptive(phone: 12.0, tablet: 24.0);

    return async.when(
      loading:
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CupertinoActivityIndicator(),
            ),
          ),
      error:
          (e, _) => Center(
            child: Text(
              'Search failed',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
      data: (EnhancedSearchResult results) {
        if (tab == _SearchTab.players) {
          final players =
              results.playerResults
                  .map((r) => r.player)
                  .whereType<SearchPlayer>()
                  .toList();
          // Also surface allPlayers when playerResults empty but cache has hits.
          final list =
              players.isNotEmpty
                  ? players
                  : results.allPlayers.take(40).toList();

          if (list.isEmpty) {
            return _EmptyQuery(label: 'No players match "$query"');
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
            itemCount: list.length,
            separatorBuilder:
                (_, __) => Divider(
                  height: 1,
                  color: context.colors.divider.withValues(alpha: 0.45),
                ),
            itemBuilder: (context, i) {
              final p = list[i];
              return _PlayerTile(player: p, onTap: () => onPlayer(p));
            },
          );
        }

        final events =
            results.tournamentResults.map((r) => r.tournament).toList();
        if (events.isEmpty) {
          return _EmptyQuery(label: 'No events match "$query"');
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
          itemCount: events.length,
          itemBuilder: (context, i) {
            final event = events[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EventCard(
                tourEventCardModel: event,
                heroTagSuffix: 'global-search-${event.id}',
                onTap: () => onEvent(event),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyQuery extends StatelessWidget {
  const _EmptyQuery({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.onTap});

  final SearchPlayer player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = player.title?.trim();
    final subtitle = [
      if (title != null && title.isNotEmpty) title,
      if (player.fed != null && player.fed!.isNotEmpty) player.fed,
      if (player.rating != null && player.rating! > 0) '${player.rating}',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surface.withValues(alpha: 0.6),
                ),
                child: Icon(
                  CupertinoIcons.person_fill,
                  size: 20,
                  color: context.colors.iconSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: context.colors.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
