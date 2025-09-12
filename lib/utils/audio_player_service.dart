import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  
  late final AudioSource pieceMoveSfx;
  
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
    ]);
    
    pieceMoveSfx = results[0];
  }
}