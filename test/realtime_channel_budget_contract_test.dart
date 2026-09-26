import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Supabase Realtime refuses a connection's 101st channel with
/// `ChannelRateLimitReached: Too many channels`, and from then on newly
/// visible boards stop updating live. Phones reached that limit during the
/// 2026 Olympiad because StreamProviders disposed before their first snapshot
/// never released their channel (see `lib/utils/owned_stream.dart`). These
/// rules keep the per-connection channel count bounded by what is on screen.
void main() {
  final providers = _streamProviderDeclarations();

  test('the scan sees the Realtime stream providers it guards', () {
    expect(
      providers.map((provider) => provider.name),
      containsAll(<String>[
        'gameUpdatesStreamProvider',
        'gameUpdatesBatchStreamProvider',
        'liveGameUpdateStreamProvider',
        'roundMetadataChangesProvider',
        'liveRoundsIdProvider',
        'liveTourIdProvider',
        'liveSettingsProvider',
        'configuredLiveGroupBroadcastIdsProvider',
        'liveGroupBroadcastIdsProvider',
        'libraryFoldersStreamProvider',
      ]),
    );
  });

  test('every StreamProvider owns the subscription to its source', () {
    final unowned = providers
        .where((provider) => !provider.ownsItsSource)
        .map((provider) => '${provider.location} ${provider.name}')
        .toList();

    expect(
      unowned,
      isEmpty,
      reason:
          'Return the stream through ownedStream(ref, source) '
          '(lib/utils/owned_stream.dart). Riverpod 2.6 keeps a StreamProvider '
          'source subscribed forever when an autoDispose provider is disposed '
          'before the first value, which leaks one Realtime channel each time '
          'a card or board is scrolled past while loading.',
    );
  });

  test('single-game Realtime streams stay on the focused board', () {
    const singleGameProviders = <String>[
      'gameUpdatesStreamProvider(',
      'liveGameUpdateStreamProvider(',
    ];
    const allowed = <String>{
      'lib/screens/chessboard/provider/game_pgn_stream_provider.dart',
      'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
    };

    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      if (allowed.contains(file.path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (singleGameProviders.any(lines[i].contains)) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A single-game stream is one Realtime channel per game. Multi-game '
          'surfaces (For You, the Games tab, player, favourite and countrymen '
          'lists, the board game strip) must watch gameUpdatesBatchStreamProvider '
          'through liveBatchKeysForGames, which puts 25 games on one channel.',
    );
  });

  test('Realtime table streams are only opened by repositories', () {
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      if (file.path.startsWith('lib/repository/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('.stream(primaryKey')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Open Supabase `.stream()` subscriptions in lib/repository/ and '
          'expose them through a StreamProvider that uses ownedStream.',
    );
  });
}

class _StreamProviderDeclaration {
  _StreamProviderDeclaration({
    required this.location,
    required this.name,
    required this.body,
  });

  final String location;
  final String name;
  final String body;

  bool get ownsItsSource {
    if (body.contains('ownedStream(')) return true;
    // Hand-owned: the provider listens to its source and cancels it itself.
    if (body.contains('ref.onDispose(') && body.contains('.cancel()')) {
      return true;
    }
    // A generator that yields before its first await emits a value before
    // Riverpod can dispose it, so it never reaches the leaking path.
    return _yieldsBeforeAwait.hasMatch(body);
  }
}

final _yieldsBeforeAwait = RegExp(r'async\*\s*\{\s*(//[^\n]*\n\s*)*yield\b');
final _declarationStart = RegExp(r'^final\s+(\w+)\s*=\s*(.*)$');
final _streamProviderType = RegExp(r'^(AutoDispose)?StreamProvider\b');
final _closingLine = RegExp(r'^[)\]}>]');

Iterable<File> _libDartFiles() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            !file.path.endsWith('.g.dart') &&
            !file.path.endsWith('.freezed.dart'),
      );
}

List<_StreamProviderDeclaration> _streamProviderDeclarations() {
  final declarations = <_StreamProviderDeclaration>[];
  for (final file in _libDartFiles()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _declarationStart.firstMatch(lines[i]);
      if (match == null) continue;

      // `dart format` may move the provider type onto the line after `=`.
      final sameLine = match.group(2)!.trim();
      final type = sameLine.isEmpty && i + 1 < lines.length
          ? lines[i + 1].trim()
          : sameLine;
      if (!_streamProviderType.hasMatch(type)) continue;

      // The declaration runs until the next top-level item.
      final body = StringBuffer()..writeln(lines[i]);
      for (var j = i + 1; j < lines.length; j++) {
        final line = lines[j];
        if (line.isNotEmpty &&
            !line.startsWith(' ') &&
            !_closingLine.hasMatch(line)) {
          break;
        }
        body.writeln(line);
      }

      declarations.add(
        _StreamProviderDeclaration(
          location: '${file.path}:${i + 1}',
          name: match.group(1)!,
          body: body.toString(),
        ),
      );
    }
  }
  return declarations;
}
