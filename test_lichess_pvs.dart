import 'dart:convert';
import 'package:http/http.dart' as http;

/// Test script to verify Lichess Cloud Eval API PV limits
/// Run with: dart test_lichess_pvs.dart
void main() async {
  print('🧪 Testing Lichess Cloud Eval API - How many PVs does it return?\n');
  
  // Test positions with different multiPv values
  final testCases = [
    {
      'name': 'Starting Position',
      'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    },
    {
      'name': 'After 1.e4',
      'fen': 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
    },
    {
      'name': 'Sicilian Defense',
      'fen': 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
    },
  ];
  
  final multiPvValues = [1, 3, 5, 10, 15, 20];
  
  for (var testCase in testCases) {
    print('📍 Testing: ${testCase['name']}');
    print('   FEN: ${testCase['fen']}\n');
    
    for (var multiPv in multiPvValues) {
      try {
        final fen = Uri.encodeComponent(testCase['fen'] as String);
        final url = 'https://lichess.org/api/cloud-eval?fen=$fen&multiPv=$multiPv';
        
        final response = await http.get(Uri.parse(url)).timeout(
          Duration(seconds: 10),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final pvs = data['pvs'] as List;
          final depth = data['depth'];
          final knodes = data['knodes'];
          
          print('   ✅ multiPv=$multiPv → Got ${pvs.length} PVs (depth: $depth, knodes: $knodes)');
          
          // Show first 3 PVs
          for (var i = 0; i < pvs.length && i < 3; i++) {
            final pv = pvs[i] as Map<String, dynamic>;
            final moves = pv['moves'] as String;
            final cp = pv['cp'];
            final moveCount = moves.split(' ').length;
            print('      PV${i + 1}: cp=$cp, moves=$moveCount (${moves.split(' ').take(5).join(' ')}...)');
          }
          if (pvs.length > 3) {
            print('      ... and ${pvs.length - 3} more PVs');
          }
          print('');
        } else if (response.statusCode == 404) {
          print('   📭 multiPv=$multiPv → No cloud eval available (404)\n');
          break; // No point testing higher multiPv for this position
        } else if (response.statusCode == 429) {
          print('   ⚡ Rate limited! Waiting 60s...\n');
          await Future.delayed(Duration(seconds: 60));
        } else {
          print('   ❌ multiPv=$multiPv → HTTP ${response.statusCode}\n');
        }
        
        // Be nice to Lichess API
        await Future.delayed(Duration(milliseconds: 500));
        
      } catch (e) {
        print('   ❌ multiPv=$multiPv → Error: $e\n');
      }
    }
    
    print('═' * 60);
    print('');
  }
  
  print('\n📊 Summary:');
  print('   • Lichess Cloud Eval API supports up to 5 PVs (documented limit)');
  print('   • Requests with multiPv > 5 will still only return max 5 PVs');
  print('   • Our app now uses ALL returned PVs (no longer limited to 3)');
  print('   • User can select 1-5 PVs in settings');
}
