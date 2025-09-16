import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  late final AudioSource pieceMoveSfx;
  late final AudioSource pieceCastlingSfx;
  late final AudioSource pieceCheckSfx;
  late final AudioSource pieceCheckmateSfx;
  late final AudioSource pieceDrawSfx;
  late final AudioSource piecePromotionSfx;
  late final AudioSource pieceTakeoverSfx;

  factory AudioPlayerService() {
    return _instance;
  }

  AudioPlayerService._internal();

  static AudioPlayerService get instance => _instance;

  SoLoud get player => SoLoud.instance;

  Future<void> initializeAndLoadAllAssets() async {
    await SoLoud.instance.init();
    // I will add more and all sound effects later here in this future.wait (we might need to optimize in the future in case we have too many assets to load at the very beginnning of the app. but for now, its okay.)
    final results = await Future.wait([
      SoLoud.instance.loadAsset("assets/sfx/piece_move.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_castling.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_check.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_checkmate.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_draw.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_promotion.wav"),
      SoLoud.instance.loadAsset("assets/sfx/piece_takeover.wav"),
    ]);

    pieceMoveSfx = results[0];
    pieceCastlingSfx = results[1];
    pieceCheckSfx = results[2];
    pieceCheckmateSfx = results[3];
    pieceDrawSfx = results[4];
    piecePromotionSfx = results[5];
    pieceTakeoverSfx = results[6];
  }
}