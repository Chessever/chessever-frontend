import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/news/news_rich_blocks.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- fixtures
// Snapshots mirror chessever_web_frontend/test/news-rich-content.test.ts.

String _token(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

String _legacyMarker(Object json) => '<!-- news-results: ${_token(json)} -->';

String _resultsMarker(Object json, [int version = 2]) =>
    '<!-- news-results:v$version:${_token(json)} -->';

String _pairingsMarker(Object json, [int version = 1]) =>
    '<!-- news-pairings:v$version:${_token(json)} -->';

/// Deep copy, so each negative case mutates its own snapshot.
Map<String, dynamic> _clone(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

Map<String, dynamic> _legacyResults() => {
  'v': 1,
  'title': 'Round 1 · Open full results',
  'matches': [
    {
      'a': {'n': 'United States', 'f': 'USA'},
      'b': {'n': 'Kenya', 'f': 'KEN'},
      's': '3.5-0.5',
      'g': [
        {
          'n': 1,
          'a': 'Fabiano Caruana',
          'b': 'Martin Njoroge',
          'c': 'w',
          'r': '1-0',
        },
        {'n': 2, 'a': 'Levon Aronian', 'b': 'Ben Magana', 'c': 'b', 'r': '1-0'},
        {
          'n': 3,
          'a': 'Wesley So',
          'b': 'Joseph Methu',
          'c': 'w',
          'r': '0.5-0.5',
        },
        {'n': 4, 'a': 'Ray Robson', 'b': 'Ricky Sang', 'c': 'b', 'r': '1-0'},
      ],
    },
  ],
};

Map<String, dynamic> _officialResults() => {
  'v': 2,
  's': 'open',
  'r': 1,
  'src': 'https://chess-results.com/tnr1469895.aspx?lan=1&art=3&rd=1',
  'u': '16.09.2026 18:28:04',
  'm': [
    {
      'n': 1,
      'a': ['Kiribati', 'KIR', 206, '0'],
      'b': ['Sudan', 'SUD', 102, '3'],
      'g': [
        [
          1,
          'Player A',
          '',
          0,
          'w',
          'Player E',
          'FM',
          2100,
          'b',
          '0-1',
          'played',
        ],
        [
          2,
          'Player B',
          '',
          0,
          'b',
          'Player F',
          'FM',
          2190,
          'w',
          '0-0',
          'not_played',
        ],
        [
          3,
          'Player C',
          '',
          0,
          'w',
          'Player G',
          '',
          2000,
          'b',
          '0-1',
          'forfeit',
        ],
        [4, 'Player D', '', 0, 'b', 'Player H', '', 2000, 'w', '0-1', 'played'],
      ],
    },
  ],
  'np': [
    ['Angola', 'ANG', 91, 'not_paired'],
  ],
};

Map<String, dynamic> _officialPairings() => {
  'v': 1,
  's': 'open',
  'r': 2,
  'src': 'https://chess-results.com/tnr1469895.aspx?lan=1&art=2&rd=2',
  'u': '16.09.2026 21:05:00',
  'm': [
    {
      'n': 1,
      'a': ['United States', 'USA', 1],
      'b': ['Georgia', 'GEO', 17],
      'g': [
        [
          1,
          'Fabiano Caruana',
          'GM',
          2789,
          'w',
          'Baadur Jobava',
          'GM',
          2675,
          'b',
        ],
        [
          2,
          'Levon Aronian',
          'GM',
          2742,
          'b',
          'Nodirbek Abdusattorov',
          'GM',
          2751,
          'w',
        ],
        [3, 'Wesley So', 'GM', 2756, 'w', 'Levan Pantsulaia', 'GM', 2560, 'b'],
        [
          4,
          'Ray Robson',
          'GM',
          2688,
          'b',
          'Mikheil Mchedlishvili',
          'GM',
          2550,
          'w',
        ],
      ],
    },
    {
      'n': 2,
      'a': ['Kenya', 'KEN', 90],
      'b': ['Canada', 'CAN', 32],
      'g': <Object>[],
    },
  ],
  'np': [
    ['Angola', 'ANG', 91, 'not_paired'],
  ],
};

const _founderContent = '''<!-- news-author: vasif-durarbayli -->

Opening paragraph.

<!-- news-section: Live video inside ChessEver -->

<!-- news-youtube: 0H_eO2Pjppc -->

Closing paragraph.''';

List<NewsBlock> _paragraphs(List<String> texts) => [
  for (final text in texts) NewsParagraphBlock(text),
];

Map<String, dynamic> _row({
  Object? id = 7,
  Object? title = 'Carlsen wins Norway Chess 2026',
  Object? summary = 'A clean sweep in Stavanger.',
  Object? content = 'Magnus Carlsen won again.',
  Object? imageUrl = 'https://cdn.example.com/cover.jpg',
  Object? publishedAt = '2026-09-16T12:00:00Z',
  Object? createdAt = '2026-09-16T11:00:00Z',
  Object? updatedAt = '2026-09-17T08:00:00Z',
  Object? sourceUrl,
}) => {
  'id': id,
  'title': title,
  'summary': summary,
  'content': content,
  'source_url': sourceUrl,
  'image_url': imageUrl,
  'status': 'published',
  'published_at': publishedAt,
  'created_at': createdAt,
  'updated_at': updatedAt,
};

FeedNews _news({
  int id = 7,
  String title = 'Carlsen wins Norway Chess 2026',
  String summary = 'A clean sweep in Stavanger.',
  String content = 'Magnus Carlsen won again.',
  String? sourceUrl,
}) => normalizeNewsRow(
  _row(
    id: id,
    title: title,
    summary: summary,
    content: content,
    imageUrl: null,
    sourceUrl: sourceUrl,
  ),
)!;

// ------------------------------------------------------------------ fakes

class _MemoryCache implements NewsCacheStore {
  NewsCacheEntry? entry;
  int writes = 0;

  @override
  Future<NewsCacheEntry?> read(String key) async => entry;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    entry = (value: value, storedAt: DateTime.now());
  }
}

class _Fetcher {
  _Fetcher(this.rows);

  List<Map<String, dynamic>> rows;
  Object? error;
  int calls = 0;

  Future<List<Map<String, dynamic>>> call(int limit) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return rows;
  }
}

// ------------------------------------------------------------------ tests

void main() {
  group('newsSlug matches the web (news.ts)', () {
    // Expected values were produced by the web's own newsSlug in Node.
    const cases = {
      'Carlsen wins Norway Chess 2026': 'carlsen-wins-norway-chess-2026',
      'Yağız Kaan Erdoğmuş beats Ding Liren!':
          'yag-z-kaan-erdogmus-beats-ding-liren',
      'Gukesh scores 5½/9 — Ju Wenjun leads':
          'gukesh-scores-51-2-9-ju-wenjun-leads',
      'İstanbul Olympiad: Round 1 · Open': 'istanbul-olympiad-round-1-open',
      '🇳🇴 Norway’s ‘Magnus’ effect': 'norway-s-magnus-effect',
      'Ǆoković? ﬁnal ＦＩＤＥ ２０２６ Grand Prix':
          'dzokovic-final-fide-2026-grand-prix',
      'Dūdā & Łukasz Øyvind Straße': 'duda-ukasz-yvind-stra-e',
      'Vasif Durarbayli — Əliyev Cup': 'vasif-durarbayli-liyev-cup',
      'Phạm Lê Thảo Nguyên wins Việt Nam championship':
          'pham-le-thao-nguyen-wins-viet-nam-championship',
      'Round 7: ① ② ③ board™ Ⅳ': 'round-7-1-2-3-board-iv',
      '!!!': 'chessever-news',
      '': 'chessever-news',
    };
    for (final entry in cases.entries) {
      test('"${entry.key}"', () {
        expect(newsSlug(entry.key), entry.value);
      });
    }

    test('caps at 120 characters without re-trimming the cut', () {
      final title = '${'x' * 118} yz long';
      expect(newsSlug(title), '${'x' * 118}-y');
    });
  });

  group('normalizeNewsRow', () {
    test('cleans fields and builds the canonical web URL', () {
      final news = normalizeNewsRow(
        _row(
          title: '  Carlsen\n\twins   Norway Chess 2026 ',
          summary: ' A clean\nsweep. ',
          content: 'First  line\r\nsame\tparagraph.\r\n\r\n\r\n  Second.  ',
        ),
      )!;
      expect(news.id, 7);
      expect(news.title, 'Carlsen wins Norway Chess 2026');
      expect(news.summary, 'A clean sweep.');
      expect(news.content, 'First line\nsame paragraph.\n\nSecond.');
      expect(news.publishedAt, DateTime.utc(2026, 9, 16, 12));
      expect(news.updatedAt, DateTime.utc(2026, 9, 17, 8));
      expect(news.imageUrl, 'https://cdn.example.com/cover.jpg');
      expect(
        news.webUrl,
        'https://chessever.com/news/7/carlsen-wins-norway-chess-2026',
      );
    });

    test('derives the summary from visible prose only (web parity)', () {
      final marker = _legacyMarker({
        'v': 1,
        'title': 'Round 1 full results',
        'matches': [
          {
            'a': {'n': 'Georgia', 'f': 'GEO'},
            'b': {'n': 'Canada', 'f': 'CAN'},
            's': '2-2',
            'g': [
              {'n': 1, 'a': 'A One', 'b': 'B One', 'c': 'w', 'r': '1-0'},
              {'n': 2, 'a': 'A Two', 'b': 'B Two', 'c': 'b', 'r': '1-0'},
              {'n': 3, 'a': 'A Three', 'b': 'B Three', 'c': 'w', 'r': '0-1'},
              {'n': 4, 'a': 'A Four', 'b': 'B Four', 'c': 'b', 'r': '0-1'},
            ],
          },
        ],
      });
      final news = normalizeNewsRow(
        _row(
          id: 77,
          title: 'Olympiad report',
          summary: null,
          content:
              'Visible report.\n\n$marker\n\n'
              '<!-- news-pairings:v1:not+base64url -->',
          imageUrl: null,
        ),
      )!;
      expect(news.summary, 'Visible report.');
      expect(news.imageUrl, isNull);
      expect(news.webUrl, 'https://chessever.com/news/77/olympiad-report');
      final blocks = newsContentBlocks(news.content);
      expect(blocks, hasLength(2));
      expect(blocks.last, isA<NewsResultsBlock>());
    });

    test('skips rows the web would not publish', () {
      expect(normalizeNewsRow(_row(id: null)), isNull);
      expect(normalizeNewsRow(_row(id: 0)), isNull);
      expect(normalizeNewsRow(_row(title: '   ')), isNull);
      expect(normalizeNewsRow(_row(content: ' \n\n \t ')), isNull);
      expect(
        normalizeNewsRow(_row(publishedAt: null, createdAt: null)),
        isNull,
      );
      // `??`, not `||`: an empty published_at does not fall back.
      expect(normalizeNewsRow(_row(publishedAt: '')), isNull);
      expect(normalizeNewsRow(_row(publishedAt: 'not a date')), isNull);
    });

    test('falls back to created_at and tolerates odd shapes', () {
      final news = normalizeNewsRow(
        _row(
          id: '12',
          publishedAt: null,
          updatedAt: null,
          imageUrl: 'javascript:alert(1)',
        ),
      )!;
      expect(news.id, 12);
      expect(news.publishedAt, DateTime.utc(2026, 9, 16, 11));
      expect(news.updatedAt, news.publishedAt);
      expect(news.imageUrl, isNull);
    });

    test('keeps source_url like the web; blank is none', () {
      final news = normalizeNewsRow(
        _row(sourceUrl: ' https://chessever.com/broadcast/a/b '),
      )!;
      expect(news.sourceUrl, 'https://chessever.com/broadcast/a/b');
      expect(normalizeNewsRow(_row())!.sourceUrl, isNull);
      expect(normalizeNewsRow(_row(sourceUrl: '  '))!.sourceUrl, isNull);
      expect(normalizeNewsRow(_row(sourceUrl: 42))!.sourceUrl, isNull);
    });

    test('round-trips through the SQLite cache encoding', () {
      final news = _news(sourceUrl: 'https://lichess.org/broadcast/x/y');
      final decoded = decodeFeedNewsCache(encodeFeedNewsCache([news]))!;
      expect(decoded, [news]);
      expect(decoded.single.sourceUrl, 'https://lichess.org/broadcast/x/y');
      expect(news == _news(), isFalse);
      expect(decodeFeedNewsCache('not json'), isNull);
      expect(decodeFeedNewsCache('[{"id":"x"}]'), isEmpty);
    });
  });

  group('rich content blocks (news-rich-content.ts parity)', () {
    test('founder marker resolves to the known byline', () {
      final author = resolveNewsAuthor(_founderContent)!;
      expect(author.displayName, 'GM Vasif Durarbayli');
      expect(author.role, 'Founder of ChessEver');
    });

    test('keeps the heading and the video, drops metadata', () {
      expect(newsContentBlocks(_founderContent), const [
        NewsParagraphBlock('Opening paragraph.'),
        NewsSectionBlock('Live video inside ChessEver'),
        NewsYoutubeBlock('0H_eO2Pjppc'),
        NewsParagraphBlock('Closing paragraph.'),
      ]);
      expect(
        newsContentText(_founderContent),
        'Opening paragraph. Live video inside ChessEver Closing paragraph.',
      );
    });

    test('a valid legacy results marker becomes one results block', () {
      final content =
          'Opening paragraph.\n\n${_legacyMarker(_legacyResults())}\n\n'
          'Closing paragraph.';
      final blocks = newsContentBlocks(content);
      expect(blocks, hasLength(3));
      final snapshot = (blocks[1] as NewsResultsBlock).snapshot;
      expect(snapshot.title, 'Round 1 · Open full results');
      expect(snapshot.matches.single.score, '3.5-0.5');
      expect(snapshot.matches.single.games[2].result, '0.5-0.5');
      expect(newsContentText(content), 'Opening paragraph. Closing paragraph.');
    });

    test('official results keep forfeits, not-played boards, not-paired', () {
      final parsed =
          parseNewsResultsMarker(_resultsMarker(_officialResults()))!
              as NewsResultsSnapshot;
      expect(parsed.version, 2);
      expect(parsed.title, 'Round 1 · Open full results');
      expect(parsed.matches.single.score, '0-3');
      final games = parsed.matches.single.games;
      expect(games[1].result, '0-0');
      expect(games[1].status, NewsBoardStatus.notPlayed);
      expect(games[2].status, NewsBoardStatus.forfeit);
      expect(parsed.notPaired.single.name, 'Angola');
      expect(parsed.notPaired.single.seed, 91);
    });

    test('prepared official v1 markers normalise to the richer schema', () {
      final prepared = _officialResults();
      prepared['v'] = 1;
      ((prepared['m'] as List)[0]['g'] as List)[1][9] = '—';
      final parsed =
          parseNewsResultsMarker(_resultsMarker(prepared, 1))!
              as NewsResultsSnapshot;
      expect(parsed.version, 2);
      expect(parsed.matches.single.games[1].result, '0-0');
    });

    test('official results fail closed', () {
      final badScore = _clone(_officialResults());
      ((badScore['m'] as List)[0]['b'] as List)[3] = '4';
      final badStatus = _clone(_officialResults());
      ((badStatus['m'] as List)[0]['g'] as List)[2][10] = 'abandoned';
      final badNotPlayed = _clone(_officialResults());
      ((badNotPlayed['m'] as List)[0]['g'] as List)[1][9] = '1-0';
      final badNotPaired = _clone(_officialResults());
      (badNotPaired['np'] as List)[0][3] = 'bye';
      for (final candidate in [
        badScore,
        badStatus,
        badNotPlayed,
        badNotPaired,
      ]) {
        final marker = _resultsMarker(candidate);
        expect(parseNewsResultsMarker(marker), isNull);
        expect(
          newsContentBlocks('Before.\n\n$marker\n\nAfter.'),
          _paragraphs(['Before.', 'After.']),
        );
      }
    });

    test('official pairings accept four boards or pending boards', () {
      final marker = _pairingsMarker(_officialPairings());
      final parsed = parseNewsResultsMarker(marker)! as NewsPairingsSnapshot;
      expect(parsed.title, 'Round 2 · Open full pairings');
      expect(parsed.matches, hasLength(2));
      expect(parsed.matches[0].games, hasLength(4));
      expect(parsed.matches[1].games, isEmpty);
      expect(parsed.notPaired.single.name, 'Angola');
      expect(newsContentText('Before.\n\n$marker\n\nAfter.'), 'Before. After.');
    });

    test('official pairings fail closed', () {
      Map<String, dynamic> variant(void Function(Map<String, dynamic>) edit) {
        final copy = _clone(_officialPairings());
        edit(copy);
        return copy;
      }

      final candidates = [
        variant(
          (s) => s['src'] = 'https://example.com/tnr1469895.aspx?art=2&rd=2',
        ),
        variant(
          (s) =>
              s['src'] = 'https://chess-results.com/tnr1469895.aspx?art=3&rd=2',
        ),
        variant((s) => ((s['m'] as List)[0]['a'] as List)[1] = 'ZZZ'),
        variant((s) => (s['m'] as List)[1]['a'] = (s['m'] as List)[0]['a']),
        variant(
          (s) => ((s['m'] as List)[0]['g'] as List)[1][1] =
              ((s['m'] as List)[0]['g'] as List)[0][1],
        ),
        variant((s) => ((s['m'] as List)[0]['g'] as List).removeLast()),
        variant((s) => ((s['m'] as List)[0]['g'] as List)[0][8] = 'w'),
      ];
      for (final candidate in candidates) {
        final marker = _pairingsMarker(candidate);
        expect(parseNewsResultsMarker(marker), isNull, reason: '$candidate');
        expect(
          newsContentBlocks('Before.\n\n$marker\n\nAfter.'),
          _paragraphs(['Before.', 'After.']),
        );
      }
    });

    test('malformed structured markers are stripped, never shown', () {
      final badLegacy = _legacyResults();
      (badLegacy['matches'] as List)[0]['s'] = '4-0';
      final markers = [
        '<!-- news-pairings:v1:not+base64url -->',
        _pairingsMarker({..._officialPairings(), 'secret': 'must not render'}),
        '<!-- news-pairings:v1:${'a' * 180001} -->',
        _legacyMarker(badLegacy),
        '<!-- news-results: not+base64url -->',
      ];
      for (final marker in markers) {
        expect(parseNewsResultsMarker(marker), isNull);
        expect(
          newsContentBlocks('Lead.\n\n$marker\n\nTail.'),
          _paragraphs(['Lead.', 'Tail.']),
        );
      }
    });

    test('unknown authors and malformed media markers stay harmless', () {
      const content =
          '<!-- news-author: someone-else -->\n\n'
          '<!-- related: [Event](/broadcast/example) -->\n\n'
          '<!-- country-relevance: USA=subject -->\n\n'
          '<!-- news-youtube: not a valid id -->';
      expect(resolveNewsAuthor(content), isNull);
      // The web keeps the malformed marker as prose...
      expect(
        newsContentBlocks(content),
        _paragraphs(['<!-- news-youtube: not a valid id -->']),
      );
      // ...the app reader never shows a raw comment.
      expect(newsReaderBlocks(content), isEmpty);
    });
  });

  group('reader blocks fall back gracefully', () {
    test('merges prose runs so markdown lists and tables survive', () {
      const content =
          'Intro with **bold**.\n\n- one\n- two\n\n'
          '<!-- news-section: Standings -->\n\n'
          '| Player | Pts |\n|---|---|\n| Carlsen | 7 |';
      expect(newsReaderBlocks(content), const [
        NewsMarkdownBlock('Intro with **bold**.\n\n- one\n- two'),
        NewsSectionBlock('Standings'),
        NewsMarkdownBlock('| Player | Pts |\n|---|---|\n| Carlsen | 7 |'),
      ]);
    });

    test('JSON records become a table; other JSON is dropped', () {
      const content =
          'Standings after round 5.\n\n'
          '```standings\n'
          '[{"player":"Carlsen","pts":4.5},{"player":"Gukesh","pts":4}]\n'
          '```\n\n'
          '```json\n{"nested":{"deep":true}}\n```\n\n'
          '{"v":1,"raw":"payload"}\n\n'
          'Inline <!-- editor note --> comment.';
      final blocks = newsReaderBlocks(content);
      expect(blocks, hasLength(1));
      final markdown = (blocks.single as NewsMarkdownBlock).markdown;
      expect(markdown, contains('| player | pts |'));
      expect(markdown, contains('| Carlsen | 4.5 |'));
      expect(markdown, contains('Inline  comment.'));
      expect(markdown, isNot(contains('{')));
      expect(markdown, isNot(contains('<!--')));
      expect(markdown, isNot(contains('```')));
    });

    test('plain fenced code is left alone', () {
      const content = '```\n1. e4 e5 2. Nf3\n```';
      expect(newsReaderBlocks(content), const [NewsMarkdownBlock(content)]);
    });
  });

  group('links', () {
    test('relative and absolute chessever links route in the app', () {
      Uri? route(String href) => newsInAppRoute(resolveNewsHref(href)!);
      expect(
        route('/broadcast/norway-chess/abc123').toString(),
        'https://chessever.com/broadcast/norway-chess/abc123',
      );
      expect(
        route('https://www.chessever.com/player/magnus-carlsen/1503014.'),
        Uri.parse('https://chessever.com/player/magnus-carlsen/1503014'),
      );
      expect(
        route('https://chessever.com/broadcast/a/b/standings.png'),
        Uri.parse('https://chessever.com/broadcast/a/b?tab=standings'),
      );
      expect(
        route('https://chessever.com/api/og/player?fideId=1503014'),
        Uri.parse('https://chessever.com/player/1503014'),
      );
      expect(route('/calendar'), isNull);
      expect(route('https://lichess.org/broadcast/x/y'), isNull);
    });

    test('unsafe or empty targets are ignored', () {
      expect(resolveNewsHref('javascript:alert(1)'), isNull);
      expect(resolveNewsHref('#top'), isNull);
      expect(resolveNewsHref(''), isNull);
      expect(resolveNewsHref(null), isNull);
    });

    test('source link matches news.ts normalizeInternalHref', () {
      expect(
        normalizeNewsInternalHref(
          'https://chessever.com/broadcast/olympiad/r1/standings.png',
        ),
        '/broadcast/olympiad/r1?tab=standings',
      );
      expect(
        normalizeNewsInternalHref(
          'https://chessever.com/broadcast/a/b/player/c/profile.png',
        ),
        '/broadcast/a/b/player/c',
      );
      expect(
        normalizeNewsInternalHref(
          'https://chessever.com/api/og/player-profile?fideId=%201503014',
        ),
        '/player/1503014',
      );
      expect(
        normalizeNewsInternalHref('https://chessever.com/api/og/player?x=1'),
        isNull,
      );
      expect(
        normalizeNewsInternalHref('/broadcast/a/b?tab=games.'),
        '/broadcast/a/b?tab=games',
      );
      expect(normalizeNewsInternalHref('https://chessever.com'), isNull);
      expect(normalizeNewsInternalHref('https://chessever.com/'), isNull);
      expect(normalizeNewsInternalHref('/news/42/x'), isNull);
      // Same origin only, exactly as `parsed.origin !== SITE_URL`.
      expect(normalizeNewsInternalHref('http://chessever.com/games/1'), null);
      expect(normalizeNewsInternalHref('https://lichess.org/x'), isNull);
      expect(normalizeNewsInternalHref('javascript:alert(1)'), isNull);
      expect(normalizeNewsInternalHref('https://chessever.com:x/'), isNull);
    });

    test('source context href and label match the article page', () {
      expect(newsSourceContextHref(_news()), isNull);
      final standings = _news(
        sourceUrl: 'https://chessever.com/broadcast/a/b/standings.png',
      );
      final href = newsSourceContextHref(standings)!;
      expect(href, '/broadcast/a/b?tab=standings');
      expect(newsSourceContextLabel(href), 'Open Standings');
      expect(newsSourceContextLabel('/broadcast/a/b'), 'Open Event');
      expect(newsSourceContextLabel('/player/1503014'), 'Open Player Profile');
      expect(newsSourceContextLabel('/games/abc'), 'Open Game');

      final outside = _news(sourceUrl: 'https://lichess.org/broadcast/x/y');
      expect(
        newsSourceContextHref(outside),
        'https://lichess.org/broadcast/x/y',
      );
      expect(
        newsSourceContextLabel(newsSourceContextHref(outside)!),
        'Open Source',
      );

      // Internal hrefs route in the app like any article link.
      expect(
        newsInAppRoute(resolveNewsHref(href)!),
        Uri.parse('https://chessever.com/broadcast/a/b?tab=standings'),
      );
    });

    test('another article is recognised by id', () {
      expect(newsArticleIdOf(Uri.parse('https://chessever.com/news/42/x')), 42);
      expect(newsArticleIdOf(Uri.parse('https://example.com/news/42/x')), null);
    });

    test('inline images load only from ChessEver-owned hosts', () {
      bool allowed(String src) =>
          isNewsImageSourceAllowed(resolveNewsHref(src)!);

      expect(allowed('/images/board.png'), isTrue);
      expect(allowed('https://www.chessever.com/a.png'), isTrue);
      expect(allowed('https://i.ytimg.com/vi/abc/hqdefault.jpg'), isTrue);
      expect(
        allowed(
          'https://oelbsuggrzyqwzmvidju.supabase.co'
          '/storage/v1/object/public/news/cover.png',
        ),
        isTrue,
      );
      expect(
        allowed(
          'https://odmekzlfunfocvedqusl.supabase.co'
          '/storage/v1/render/image/public/news/cover.png?width=800',
        ),
        isTrue,
      );

      // Third parties, look-alikes and tricks stay links.
      expect(allowed('https://tracker.example/pixel.gif'), isFalse);
      expect(allowed('https://chessever.com.evil.test/a.png'), isFalse);
      expect(allowed('https://chessever.com@evil.test/a.png'), isFalse);
      expect(allowed('https://chessever.com:8443/a.png'), isFalse);
      expect(allowed('http://chessever.com/a.png'), isFalse);
      expect(
        allowed('https://other.supabase.co/storage/v1/object/public/a.png'),
        isFalse,
      );
      expect(
        allowed('https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/x'),
        isFalse,
      );
    });
  });

  group('FeedNewsRepository', () {
    test('first load fetches, caches, and reuses instances', () async {
      final cache = _MemoryCache();
      final fetch = _Fetcher([_row(), _row(id: 8, title: 'Second')]);
      final repo = FeedNewsRepository(fetchRows: fetch.call, cache: cache);

      expect(await repo.readCached(), isNull);
      final first = (await repo.refresh())!;
      expect(first.items.map((n) => n.id), [7, 8]);
      await Future<void>.delayed(Duration.zero);
      expect(cache.writes, 1);

      // Nothing changed: the very same list comes back.
      final same = (await repo.refresh())!;
      expect(identical(same.items, first.items), isTrue);

      // One article edited: the other keeps its instance.
      fetch.rows = [_row(summary: 'Edited.'), _row(id: 8, title: 'Second')];
      final edited = (await repo.refresh())!;
      expect(identical(edited.items, first.items), isFalse);
      expect(edited.items[0].summary, 'Edited.');
      expect(identical(edited.items[1], first.items[1]), isTrue);
    });

    test('a missing news table is an empty list, other errors fail', () async {
      final fetch = _Fetcher(const [])
        ..error = const PostgrestException(
          message: 'Could not find the table public.news in the schema cache',
          code: 'PGRST205',
        );
      final repo = FeedNewsRepository(
        fetchRows: fetch.call,
        cache: _MemoryCache(),
      );
      expect((await repo.refresh())!.items, isEmpty);

      fetch.error = const PostgrestException(
        message: 'relation "public.news" does not exist',
        code: '42P01',
      );
      expect((await repo.refresh())!.items, isEmpty);

      fetch.error = const PostgrestException(message: 'boom', code: '500');
      expect(await repo.refresh(), isNull);
    });

    test('a missing column is a failed fetch, never an empty table', () async {
      final cache = _MemoryCache();
      final fetch = _Fetcher(const [])
        ..error = const PostgrestException(
          message: 'column news.source_url does not exist',
          code: '42703',
        );
      final repo = FeedNewsRepository(fetchRows: fetch.call, cache: cache);
      expect(await repo.refresh(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(cache.writes, 0);
      expect(await repo.readCached(), isNull);
    });

    test(
      'provider paints a fresh cache without touching the network',
      () async {
        final cache = _MemoryCache()
          ..entry = (
            value: encodeFeedNewsCache([_news()]),
            storedAt: DateTime.now(),
          );
        final fetch = _Fetcher(const []);
        final container = ProviderContainer(
          overrides: [
            feedNewsRepositoryProvider.overrideWithValue(
              FeedNewsRepository(fetchRows: fetch.call, cache: cache),
            ),
          ],
        );
        addTearDown(container.dispose);

        final items = await container.read(feedNewsProvider.future);
        expect(items.single.title, 'Carlsen wins Norway Chess 2026');
        expect(fetch.calls, 0);
      },
    );

    test('provider shows a stale cache, then refreshes behind it', () async {
      final cache = _MemoryCache()
        ..entry = (
          value: encodeFeedNewsCache([_news()]),
          storedAt: DateTime.now().subtract(const Duration(hours: 2)),
        );
      final fetch = _Fetcher([_row(id: 9, title: 'Fresh story')]);
      final container = ProviderContainer(
        overrides: [
          feedNewsRepositoryProvider.overrideWithValue(
            FeedNewsRepository(fetchRows: fetch.call, cache: cache),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(feedNewsProvider, (_, _) {});
      addTearDown(sub.close);

      final stale = await container.read(feedNewsProvider.future);
      expect(stale.single.id, 7);
      // Background refresh lands and the provider rebuilds with it.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final fresh = await container.read(feedNewsProvider.future);
      expect(fresh.single.id, 9);
      expect(fetch.calls, 1);
    });
  });

  group('widgets', () {
    testWidgets('a third-party image is a link, never fetched', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: NewsMarkdown(
                  markdown: '![Final standings](https://tracker.example/p.png)',
                  onLink: opened.add,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      final link = find.textContaining('Final standings', findRichText: true);
      expect(link, findsOneWidget);
      expect(
        find.textContaining('tracker.example', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(link);
      expect(opened, [Uri.parse('https://tracker.example/p.png')]);
    });

    const body =
        'Magnus Carlsen **won** the event. See the '
        '[standings](/broadcast/norway-chess/abc123?tab=standings).\n\n'
        '- Carlsen 7\n- Gukesh 6.5';

    Future<void> pumpReader(WidgetTester tester, FeedNews news) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedNewsProvider.overrideWith((ref) async => [news]),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return NewsReaderScreen(news: news);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('reader renders markdown and a results table', (tester) async {
      final news = _news(
        content:
            '$body\n\n${_legacyMarker(_legacyResults())}\n\n'
            '${_resultsMarker({'v': 2, 'broken': true})}\n\n'
            'Closing words.',
      );
      await pumpReader(tester, news);

      expect(find.text('Carlsen wins Norway Chess 2026'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNWidgets(2));
      expect(
        find.textContaining('the event', findRichText: true),
        findsWidgets,
      );
      expect(find.text('Round 1 · Open full results'), findsOneWidget);
      expect(find.text('United States'), findsOneWidget);
      expect(
        find.textContaining('news-results', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('{', findRichText: true), findsNothing);

      // A match row opens to its boards.
      expect(find.text('Fabiano Caruana'), findsNothing);
      await tester.tap(find.text('United States'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Fabiano Caruana'), findsOneWidget);
      expect(find.text('White'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Open on chessever.com'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open on chessever.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reader shows the source link like the web', (tester) async {
      await pumpReader(
        tester,
        _news(
          content: body,
          sourceUrl: 'https://chessever.com/broadcast/a/b/standings.png',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Open Standings'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open Standings'), findsOneWidget);
      expect(find.text('Open on chessever.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a source that is the article itself is left out', (
      tester,
    ) async {
      await pumpReader(
        tester,
        _news(content: body, sourceUrl: '/news/7/carlsen-wins'),
      );
      await tester.scrollUntilVisible(
        find.text('Open on chessever.com'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open Source'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('feed page shows the headline and opens the reader', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final news = _news(
        title:
            'A very long headline about the Olympiad that keeps going on '
            'and on so that it has to shrink to stay inside three lines',
        content: body,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedNewsProvider.overrideWith((ref) async => [news]),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: SizedBox(
                    height: 640,
                    child: FeedNewsPage(
                      news: news,
                      isCurrent: true,
                      isVisible: true,
                      onRequestNext: () {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining('ChessEver News', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('A clean sweep in Stavanger.'), findsOneWidget);
      final title = tester.widget<Text>(find.text(news.title));
      // A headline is one or two lines, never a staircase.
      expect(title.maxLines, 2);
      expect(title.style!.fontSize, lessThan(30));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Read'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NewsReaderScreen), findsOneWidget);
    });
  });
}
