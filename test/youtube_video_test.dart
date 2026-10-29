import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/utils/youtube_video.dart';

void main() {
  test(
    'watch, share, embed, shorts and fragment timestamps normalize equally',
    () {
      for (final url in [
        'https://youtu.be/abcdefghijk?t=1h2m3s',
        'https://www.youtube.com/watch?v=abcdefghijk&t=3723s&si=tracking',
        'https://www.youtube.com/embed/abcdefghijk?start=3723',
        'https://youtube.com/shorts/abcdefghijk#t=3723',
      ]) {
        final video = YoutubeVideo.parse(url);
        expect(video.start, 3723);
        expect(
          video.url.toString(),
          'https://www.youtube.com/watch?v=abcdefghijk&start=3723',
        );
      }
    },
  );
  test('all supported playback settings survive a URL round trip', () {
    final video = YoutubeVideo.parse(
      'https://www.youtube.com/watch?v=abcdefghijk&start=75&end=300&autoplay=1&mute=1&loop=1&cc_load_policy=1&cc_lang_pref=pt-BR&hl=tr',
    );
    final again = YoutubeVideo.parse(video.url.toString());
    expect(again.start, 75);
    expect(again.end, 300);
    expect(
      again.autoplay && again.muted && again.loop && again.captions,
      isTrue,
    );
    expect(again.captionLanguage, 'pt-BR');
    expect(again.playerLanguage, 'tr');
    expect(YoutubeVideo.time('01:02:03'), 3723);
    expect(YoutubeVideo.time('12:30'), 750);
  });
  test(
    'invalid providers, ranges, flags and injected parameters are refused',
    () {
      for (final url in [
        'https://youtube.com.evil.test/watch?v=abcdefghijk',
        'https://user@youtube.com/watch?v=abcdefghijk',
        'http://youtu.be/abcdefghijk',
        'https://youtu.be/abcdefghijk?start=-1',
        'https://youtu.be/abcdefghijk?start=60&end=20',
        'https://youtu.be/abcdefghijk?autoplay=yes',
        'https://youtu.be/abcdefghijk?hl=%22%3E%3Cscript%3E',
      ]) {
        expect(
          () => YoutubeVideo.parse(url),
          throwsFormatException,
          reason: url,
        );
      }
      expect(() => YoutubeVideo.time('1:99'), throwsFormatException);
    },
  );
}
