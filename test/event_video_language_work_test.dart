import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountedStream extends EventVideoStream {
  _CountedStream(int index, String title)
    : super(
        id: 'stream-$index',
        label: 'Channel $index',
        title: title,
        source: VideoSource.parse('https://www.twitch.tv/channel$index'),
      );

  int titleReads = 0;
  @override
  String get title {
    titleReads++;
    return super.title;
  }
}

void main() {
  for (final title in ['Hindi commentary', 'Live chess']) {
    test('50-stream selector resolves language once per stream: $title', () {
      final streams = List.generate(50, (i) => _CountedStream(i, title));
      for (final stream in streams) {
        final key = stream.languageKey;
        final flag = stream.flagCode;
        final label = stream.languageLabel;
        for (var rebuild = 0; rebuild < 100; rebuild++) {
          expect(stream.languageKey, key);
          expect(stream.flagCode, flag);
          expect(stream.languageLabel, label);
        }
        expect(
          stream.titleReads,
          1,
          reason:
              'Unchanged metadata must not re-run language regexes, including unknown languages',
        );
      }
    });
  }
}
