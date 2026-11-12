import 'package:chessever2/watch/core/watch_replay.dart';
import 'package:chessever2/watch/core/watch_sound.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a move sounds by the phone rule', () {
    expect(watchSoundForSan('Nf3'), WatchSound.move);
    expect(watchSoundForSan('exd5'), WatchSound.takeover);
    expect(watchSoundForSan('O-O'), WatchSound.castling);
    expect(watchSoundForSan('O-O-O'), WatchSound.castling);
    expect(watchSoundForSan('e8=Q'), WatchSound.promotion);
    expect(watchSoundForSan('Bxf7+'), WatchSound.check);
    expect(watchSoundForSan('Qh7#'), WatchSound.checkmate);
    expect(watchSoundForSan('O-O+'), WatchSound.check);
    expect(watchSoundForSan('exf8=Q#'), WatchSound.checkmate);
    expect(watchSoundForSan('exf8=Q'), WatchSound.promotion);
  });

  test('replay positions carry their SAN', () {
    final positions = watchReplayPositions('1. e4 d5 2. exd5 Qxd5 3. Nc3 *');
    expect(positions.first.san, '');
    expect(positions.map((p) => p.san).skip(1), [
      'e4',
      'd5',
      'exd5',
      'Qxd5',
      'Nc3',
    ]);
  });

  test('every phone sound is bundled as WAV audio', () async {
    for (final sound in WatchSound.values) {
      final bytes = await rootBundle.load('assets/sfx/piece_${sound.name}.wav');
      expect(bytes.lengthInBytes, greaterThan(44), reason: sound.name);
      expect(
        bytes.getUint32(0),
        0x52494646, // RIFF
        reason: sound.name,
      );
      expect(bytes.getUint32(8), 0x57415645, reason: sound.name); // WAVE
    }
  });

  test(
    'fast review sounds once per detent window and stop clears it',
    () async {
      var now = Duration.zero;
      final played = <WatchSound>[];
      WatchSounds.debugPlayer = played.add;
      WatchSounds.debugNow = () => now;
      WatchSounds.shared.debugReset();
      addTearDown(() {
        WatchSounds.debugPlayer = null;
        WatchSounds.debugNow = null;
        WatchSounds.shared.debugReset();
      });
      await WatchSounds.shared.warmUp();
      WatchSounds.shared.play(WatchSound.move);
      now += WatchSounds.spacing - const Duration(microseconds: 1);
      WatchSounds.shared.play(WatchSound.takeover);
      expect(played, [WatchSound.move]);
      now += const Duration(microseconds: 1);
      WatchSounds.shared.play(WatchSound.check);
      expect(played, [WatchSound.move, WatchSound.check]);
      WatchSounds.shared.stop();
      WatchSounds.shared.play(WatchSound.move);
      expect(played, [WatchSound.move, WatchSound.check, WatchSound.move]);
    },
  );
}
