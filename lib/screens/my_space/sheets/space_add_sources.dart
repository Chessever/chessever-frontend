import 'dart:math' as math;

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/favorites/widgets/favorite_player_search_suggestion.dart'
    show favoritePlayerSearchProvider;
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show mostLikedProvider;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show formatOpeningMovePath;
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show PlayerView;
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart'
    show watchSpaceDraftAdded;
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/my_space/widgets/space_game_rows.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceText;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart'
    show openingSearchSpaceDraft, searchEventSpaceDraft;
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The group the Openings suggestions list what My Space already holds under.
const String kSpaceSheetAddedLabel = 'In My Space';

/// What a row's board editor button says to a screen reader.
const String kSpaceSheetEditorLabel = 'Open in board editor';

/// What the search field offers to find, per row.
String spaceSheetSearchHint(SpaceSection section) => switch (section) {
  SpaceSection.players => 'Search players',
  SpaceSection.events => 'Search events',
  SpaceSection.games => 'Search by player or event',
  SpaceSection.openings => 'Search openings or ECO',
  SpaceSection.library => 'Search your Library',
  _ => 'Search',
};

/// One line of the sheet's list.
sealed class SpaceSheetEntry {
  const SpaceSheetEntry();
}

/// A group heading ("Following", "Popular at 2700+").
class SpaceSheetLabel extends SpaceSheetEntry {
  const SpaceSheetLabel(this.text);
  final String text;
}

/// A quiet line in place of rows: still loading, or nothing matched.
class SpaceSheetNote extends SpaceSheetEntry {
  const SpaceSheetNote(this.text);
  final String text;
}

/// Something to add.
class SpaceSheetRow extends SpaceSheetEntry {
  const SpaceSheetRow({
    required this.draft,
    required this.title,
    this.meta,
    this.leading,
    this.editorFen,
    this.addLabel,
  });

  final SpaceShortcut draft;
  final String title;
  final String? meta;
  final Widget? leading;

  /// A position the row can also open in the board editor.
  final String? editorFen;

  /// Overrides "Add {title}" for a screen reader.
  final String? addLabel;
}

/// A game to add, drawn with the game card's own player rows: flag, title,
/// name, rating and result, the way every game card in the app shows them.
class SpaceSheetGame extends SpaceSheetEntry {
  const SpaceSheetGame({required this.draft, required this.game, this.meta});

  final SpaceShortcut draft;
  final GamesTourModel game;

  /// The event, under the players.
  final String? meta;
}

/// The row's suggestions and search results, as one scrolling list.
class SpaceAddSources extends ConsumerWidget {
  const SpaceAddSources({
    super.key,
    required this.section,
    required this.query,
    required this.onToggle,
    this.onOpenEditor,
    this.onNotice,
    this.pinnedAtOpen = const <String>{},
  });

  final SpaceSection section;
  final String query;
  final Future<void> Function(SpaceShortcut draft) onToggle;
  final ValueChanged<String>? onOpenEditor;
  final ValueChanged<String>? onNotice;

  /// The keys My Space held when the sheet opened. The Openings suggestions
  /// list what is not among them first and the rest after, marked as added;
  /// the order holds while the sheet is open, so a row never jumps away from
  /// the finger that just toggled it.
  final Set<String> pinnedAtOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = switch (section) {
      SpaceSection.players => _players(ref, query),
      SpaceSection.events => _events(ref, query),
      SpaceSection.games => _games(ref, query),
      SpaceSection.openings => _openings(query, pinnedAtOpen),
      SpaceSection.library => _library(ref, query),
      _ => const <SpaceSheetEntry>[],
    };
    return ListView.builder(
      padding: EdgeInsets.only(top: 4.w, bottom: 16.w),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: entries.length,
      itemBuilder: (context, i) => switch (entries[i]) {
        SpaceSheetLabel(:final text) => _Label(text: text),
        SpaceSheetNote(:final text) => _Note(text: text),
        final SpaceSheetRow row => _Row(
          key: ValueKey<String>('row:${row.draft.key}:$i'),
          row: row,
          onToggle: onToggle,
          onOpenEditor: onOpenEditor,
        ),
        final SpaceSheetGame game => _GameRow(
          key: ValueKey<String>('game:${game.draft.key}:$i'),
          entry: game,
          onToggle: onToggle,
        ),
      },
    );
  }

  // ------------------------------------------------------------- players

  List<SpaceSheetEntry> _players(WidgetRef ref, String query) {
    if (query.length >= 2) {
      final found = ref.watch(favoritePlayerSearchProvider(query));
      return [
        const SpaceSheetLabel('Players'),
        ..._orNote(found, [
          for (final p in found.valueOrNull ?? const [])
            _playerRow(
              spacePlayerDraft(
                playerName: p.name,
                fideId: p.fideId,
                title: p.title,
                federation: p.countryCode,
                rating: p.score > 0 ? p.score : null,
              ),
            ),
        ]),
      ];
    }
    final favorites = ref.watch(favoritePlayersProviderNew);
    final country = ref.watch(countryDropdownProvider).valueOrNull;
    final top = ref.watch(spaceCountryTopPlayersProvider);
    final countrymen = country == null
        ? null
        : spaceCountrymenDraft(country.countryCode);
    final following = favorites.valueOrNull ?? const <FavoritePlayer>[];
    // Followed players already sit under Following; list each player once.
    final followedIds = {
      for (final f in following)
        if (int.tryParse(f.fideId ?? '') case final id?) id,
    };
    final topPlayers = top.valueOrNull ?? const <ChessPlayer>[];
    final topRows = <SpaceSheetEntry>[
      for (final p in topPlayers)
        if (!followedIds.contains(p.fideid))
          _playerRow(
            spacePlayerDraft(
              playerName: p.name,
              fideId: p.fideid,
              title: p.title,
              rating: p.rating,
              federation: p.country,
            ),
          ),
    ];
    return [
      if (following.isNotEmpty) ...[
        const SpaceSheetLabel('Following'),
        for (final f in following) _playerRow(spaceFavoriteDraft(f)),
      ],
      if (country != null) ...[
        SpaceSheetLabel('Top in ${country.name}'),
        if (countrymen != null)
          SpaceSheetRow(
            draft: countrymen,
            title: '${country.name} players',
            meta: 'Everyone from ${country.name}',
            leading: FederationFlag.hasVisibleFlag(country.countryCode)
                ? FederationFlag(
                    federation: country.countryCode,
                    width: 28.w,
                    height: 21.w,
                    borderRadius: BorderRadius.circular(3.w),
                  )
                : null,
          ),
        // The country row already stands for everyone: a top list that came
        // back empty (or all followed) adds nothing, not "No results".
        if (topRows.isNotEmpty)
          ...topRows
        else if (!top.hasValue)
          ..._orNote(top, topRows),
      ],
    ];
  }

  SpaceSheetRow _playerRow(SpaceShortcut draft) {
    final p = draft.params;
    final fideId = p['fideId'] is int ? p['fideId'] as int : null;
    final name = draft.title;
    return SpaceSheetRow(
      draft: draft,
      title: name,
      meta: draft.subtitle,
      leading: _Avatar(fideId: fideId, name: name),
    );
  }

  // ------------------------------------------------------------- library

  /// The Library tab's destinations, in its order, to save into My Database.
  /// Liked Games is left out: My Likes has its own tile on My Space.
  List<SpaceSheetEntry> _library(WidgetRef ref, String query) {
    final library = ref.watch(spaceLibraryFoldersProvider);
    final needle = query.toLowerCase();
    final rows = <SpaceSheetEntry>[
      for (final f in library.folders)
        if (!f.isLikedGames &&
            (needle.length < 2 || f.name.toLowerCase().contains(needle)))
          _libraryRow(spaceLibraryFolderDraft(f)),
    ];
    return [
      const SpaceSheetLabel('Your Library'),
      if (rows.isNotEmpty)
        ...rows
      else
        SpaceSheetNote(
          !library.settled
              ? 'Loading'
              : needle.length < 2
              ? 'Nothing in your Library yet'
              : 'No results',
        ),
    ];
  }

  SpaceSheetRow _libraryRow(SpaceShortcut draft) => SpaceSheetRow(
    draft: draft,
    title: draft.title,
    meta: draft.subtitle ?? 'Database',
  );

  // -------------------------------------------------------------- events

  List<SpaceSheetEntry> _events(WidgetRef ref, String query) {
    if (query.length >= 2) {
      final found = ref.watch(supabaseCombinedSearchProvider(query));
      final seen = <String>{};
      return [
        const SpaceSheetLabel('Events'),
        ..._orNote(found, [
          for (final r in found.valueOrNull?.tournamentResults ?? const [])
            if (searchEventSpaceDraft(r.tournament) case final draft?)
              if (seen.add(draft.key)) _eventRow(draft, r.tournament),
        ]),
      ];
    }
    final events = ref.watch(forYouEventsProvider.select((s) => s.events));
    final loading = ref.watch(forYouEventsProvider.select((s) => s.isLoading));
    final favoriteIds = <String>{
      for (final f in ref.watch(favoriteEventsProvider).valueOrNull ?? const [])
        f.eventId,
    };
    final byId = {for (final e in events) e.id: e};
    final drafts = spaceCurrentEventDrafts(events, favoriteIds);
    return [
      const SpaceSheetLabel('Live and upcoming'),
      if (drafts.isEmpty)
        SpaceSheetNote(loading ? 'Loading' : 'Nothing live or coming up')
      else
        for (final d in drafts) _eventRow(d, byId[d.targetId]),
    ];
  }

  SpaceSheetRow _eventRow(SpaceShortcut draft, GroupEventCardModel? model) {
    final live = model?.tourEventCategory == TourEventCategory.live;
    final parts = [
      if (live) 'Live',
      if (model?.dates.trim().isNotEmpty ?? false) model!.dates.trim(),
      if (model?.location?.trim().isNotEmpty ?? false) model!.location!.trim(),
    ];
    return SpaceSheetRow(
      draft: draft,
      title: draft.title,
      meta: parts.isEmpty ? draft.subtitle : parts.join(' · '),
    );
  }

  // --------------------------------------------------------------- games

  List<SpaceSheetEntry> _games(WidgetRef ref, String query) {
    final liked = ref.watch(likedGamesProvider);
    final ranked = ref.watch(
      mostLikedProvider(MostLikedQuery(MostLikedPeriod.today, DateTime.now())),
    );
    final needle = query.toLowerCase();
    bool matches(SpaceShortcut d) {
      if (needle.length < 2) return true;
      final hay = [
        d.title,
        d.subtitle ?? '',
        d.params['white']?.toString() ?? '',
        d.params['black']?.toString() ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(needle);
    }

    final mine = <SpaceSheetGame>[
      for (final a in (liked.valueOrNull ?? const <SavedAnalysis>[]).take(40))
        if (spaceLikedGameFace(a) case final d when matches(d))
          SpaceSheetGame(
            draft: d,
            game: spaceGameFromAnalysis(a),
            meta: d.subtitle,
          ),
    ];
    final result = ranked.valueOrNull;
    final popular = <SpaceSheetGame>[
      if (result != null && result.status == MostLikedStatus.ranked)
        for (final e in result.entries)
          if (gameSpaceShortcutDraft(
                e.game,
                subtitle: e.eventName,
                params: spaceGameCardParams(e.game),
              )
              case final d? when matches(d))
            SpaceSheetGame(draft: d, game: e.game, meta: d.subtitle),
    ];

    return [
      if (mine.isNotEmpty) ...[const SpaceSheetLabel('Your likes'), ...mine],
      const SpaceSheetLabel('Most liked today'),
      if (popular.isEmpty)
        SpaceSheetNote(
          ranked.isLoading && !ranked.hasValue ? 'Loading' : 'No games yet',
        )
      else
        ...popular,
    ];
  }

  // ------------------------------------------------------------ openings

  List<SpaceSheetEntry> _openings(String query, Set<String> pinned) {
    if (query.isNotEmpty) {
      final found = searchOpeningSuggestions(query, limit: 60);
      if (found.isEmpty) {
        return [
          const SpaceSheetLabel('All openings'),
          SpaceSheetNote(
            query.length < minimumOpeningSearchCharacters
                ? 'Type at least $minimumOpeningSearchCharacters letters'
                : 'No opening matches',
          ),
        ];
      }
      return [
        const SpaceSheetLabel('All openings'),
        for (final s in found) _searchOpeningRow(s),
      ];
    }
    // What the user can still add leads; a removed default is among it.
    final picks = spacePickerOpenings(pinned);
    return [
      if (picks.fresh.isNotEmpty) ...[
        const SpaceSheetLabel('Popular at 2700+'),
        for (final p in picks.fresh) _eliteRow(p.opening, p.draft),
      ],
      if (picks.added.isNotEmpty) ...[
        const SpaceSheetLabel(kSpaceSheetAddedLabel),
        for (final p in picks.added) _eliteRow(p.opening, p.draft),
      ],
    ];
  }

  SpaceSheetRow _eliteRow(SpaceEliteOpening o, SpaceShortcut draft) =>
      SpaceSheetRow(
        draft: draft,
        title: o.tileName,
        meta: spaceUnbrokenMoves(o.moves),
        leading: _Code(o.eco),
        // A position pin is keyed by the FEN its line reaches.
        editorFen: draft.targetId,
        addLabel: 'Save ${o.tileName} to My Space',
      );

  SpaceSheetRow _searchOpeningRow(OpeningSearchSuggestion s) {
    final draft = openingSearchSpaceDraft(s.selection, name: s.fullTitle);
    final line = resolveSpaceLine(moves: s.movePath);
    return SpaceSheetRow(
      draft: draft,
      title: s.fullTitle,
      meta: s.movePath.isEmpty
          ? s.subtitle
          : spaceUnbrokenMoves(formatOpeningMovePath(s.movePath)),
      leading: _Code(s.codeLabel),
      // A family or range with no line of its own opens on its main line.
      editorFen: line?.fen ?? spaceShortcutFen(draft),
      addLabel: 'Save ${s.fullTitle} to My Space',
    );
  }

  // --------------------------------------------------------------- common

  /// [rows], or one quiet line while [value] loads or once it came back empty.
  static List<SpaceSheetEntry> _orNote(
    AsyncValue<Object?> value,
    List<SpaceSheetEntry> rows,
  ) {
    if (rows.isNotEmpty) return rows;
    if (value.isLoading && !value.hasValue) {
      return const [SpaceSheetNote('Loading')];
    }
    if (value.hasError && !value.hasValue) {
      return const [SpaceSheetNote("Couldn't load")];
    }
    return const [SpaceSheetNote('No results')];
  }
}

/// A move line that only wraps between full moves ("1. e4 c5" stays on
/// one line): every space but the one before a move number is non-breaking.
String spaceUnbrokenMoves(String moves) {
  final tokens = moves.trim().split(RegExp(r'\s+'));
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    if (i > 0) {
      out.write(RegExp(r'^\d+\.').hasMatch(tokens[i]) ? ' ' : '\u00A0');
    }
    out.write(tokens[i]);
  }
  return out.toString();
}

// ------------------------------------------------------------------ views

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final gutter = SpaceMetricsSheet.gutter;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 18.w, gutter, 4.w),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: spaceText(
            context,
            size: 13,
            line: 18,
            weight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final gutter = SpaceMetricsSheet.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 12.w, gutter, 12.w),
      child: Text(
        text,
        style: spaceText(
          context,
          size: 14,
          line: 20,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    super.key,
    required this.row,
    required this.onToggle,
    this.onOpenEditor,
  });

  final SpaceSheetRow row;
  final Future<void> Function(SpaceShortcut draft) onToggle;
  final ValueChanged<String>? onOpenEditor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final added = watchSpaceDraftAdded(ref, row.draft);
    final colors = context.colors;
    final gutter = SpaceMetricsSheet.gutter;
    final fen = row.editorFen;
    final editor = onOpenEditor;
    void toggle() => onToggle(row.draft);

    // The toggle and the editor button each speak for themselves; the row's
    // own tap is the toggle's, made bigger.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SpaceMetricsSheet.rowMin),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, 6.w, gutter - 8, 6.w),
          child: Row(
            children: [
              if (row.leading case final leading?) ...[
                SizedBox(
                  width: SpaceMetricsSheet.lead,
                  child: Center(child: leading),
                ),
                SizedBox(width: 12.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: spaceText(
                        context,
                        size: 15,
                        line: 20,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (row.meta?.trim().isNotEmpty ?? false)
                      Text(
                        row.meta!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: spaceText(
                          context,
                          size: 13,
                          line: 18,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (fen != null && editor != null)
                _EditorButton(onTap: () => editor(fen)),
              SpaceAddToggle(
                added: added,
                onTap: toggle,
                label: added
                    ? 'Remove ${row.title} from My Space'
                    : row.addLabel ?? 'Add ${row.title}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A game to add: the game card's own two player rows (board view, the
/// size of the board screen's header), white first, with the add toggle
/// centred beside them, then the event. The rows start with the card's 16pt margin, so a
/// result sits on the sheet's gutter; a game without one keeps that column
/// empty, so flags, names and the event line up down the whole list. The
/// whole row toggles; the rows themselves take no touch.
class _GameRow extends ConsumerWidget {
  const _GameRow({super.key, required this.entry, required this.onToggle});

  final SpaceSheetGame entry;
  final Future<void> Function(SpaceShortcut draft) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = entry.draft;
    final game = entry.game;
    final added = ref.watch(spaceShortcutExistsProvider(draft.key));
    final gutter = SpaceMetricsSheet.gutter;
    // The board-view row carries its own 16pt side margin.
    final margin = 16.sp;
    final fullLead = spacePlayerRowFullLead(PlayerView.boardView);
    final lead = spacePlayerRowLead(ref, game, PlayerView.boardView);
    final meta = entry.meta?.trim() ?? '';
    void toggle() => onToggle(draft);

    Widget side({required bool white}) => Padding(
      padding: EdgeInsets.only(left: math.max(0.0, fullLead - lead)),
      child: SpaceGamePlayerRow(
        game: game,
        white: white,
        view: PlayerView.boardView,
        // A picker row, not a clock: the toggle keeps the right edge.
        showClock: false,
      ),
    );

    // One node a screen reader reads in the order the eye does (the row's
    // own layout sorts Black before White); the toggle is the action.
    String speak(PlayerCard p) => [
      p.title.trim(),
      p.name.trim(),
      if (p.rating > 0) '${p.rating}',
    ].where((s) => s.isNotEmpty).join(' ');
    final spoken = [
      speak(game.whitePlayer),
      speak(game.blackPlayer),
      if (meta.isNotEmpty) meta,
    ].where((s) => s.isNotEmpty).join(', ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SpaceMetricsSheet.rowMin),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            (gutter - margin).clamp(0.0, gutter),
            8.w,
            gutter - 8,
            8.w,
          ),
          child: Semantics(
            container: true,
            label: spoken,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The toggle centres on the two players, the game it adds,
                // not on the players plus the event.
                Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            side(white: true),
                            SizedBox(height: 6.w),
                            side(white: false),
                          ],
                        ),
                      ),
                    ),
                    SpaceAddToggle(
                      added: added,
                      onTap: toggle,
                      label: added
                          ? 'Remove ${draft.title} from My Space'
                          : 'Add ${draft.title}',
                    ),
                  ],
                ),
                if (meta.isNotEmpty)
                  ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: margin + fullLead,
                        top: 4.w,
                      ),
                      // A step under the 14pt names, which the card sets
                      // unscaled: capped so large text never lifts the
                      // event over the players.
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.15,
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: spaceText(
                            context,
                            size: 12,
                            line: 16,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
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

class _EditorButton extends StatelessWidget {
  const _EditorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'Board editor',
      excludeFromSemantics: true,
      // excludeSemantics drops the detector's own tap action, so the button
      // carries it for TalkBack and Switch Access.
      child: Semantics(
        button: true,
        label: kSpaceSheetEditorLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: SpaceMetricsSheet.toggle,
            child: Center(
              child: SpaceGlyph(
                SpaceGlyphKind.editBoard,
                size: 22,
                ink: colors.accentText,
                background: colors.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An ECO code, a range or a level, set as the row's visual.
class _Code extends StatelessWidget {
  const _Code(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        code,
        maxLines: 1,
        style: spaceText(
          context,
          size: 13,
          line: 18,
          weight: FontWeight.w700,
          color: context.colors.titleAccent,
        ),
      ),
    );
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.fideId, required this.name});

  final int? fideId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = fideId;
    final photo = id == null
        ? null
        : ref.watch(playerPhotoProvider(id)).valueOrNull;
    return PlayerInitialsAvatar(
      photoUrl: photo,
      initials: _initials(name),
      size: SpaceMetricsSheet.lead,
      isCircular: true,
    );
  }

  static String _initials(String name) {
    final clean = name.replaceAll(',', ' ').trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final only = parts.first;
      return (only.length <= 2 ? only : only.substring(0, 2)).toUpperCase();
    }
    final comma = name.contains(',');
    final first = comma ? parts[1] : parts.first;
    final last = comma ? parts.first : parts.last;
    return '${first[0]}${last[0]}'.toUpperCase();
  }
}
