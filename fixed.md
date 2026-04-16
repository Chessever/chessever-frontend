diff --git a/fixed.md b/fixed.md
index 22bc1112..e69de29b 100644
--- a/fixed.md
+++ b/fixed.md
@@ -1,8 +0,0 @@
-1. SVG Issues
-converted premium svg into PNG for proper rendering 
-created a flutter widget for analysis board svg
-
-
-
-
-3. the unsupported svg icons are replaced with a .png icon for support,
\ No newline at end of file
diff --git a/lib/screens/chessboard/provider/chess_board_screen_provider_new.dart b/lib/screens/chessboard/provider/chess_board_screen_provider_new.dart
index c06d7d36..ac54849d 100644
--- a/lib/screens/chessboard/provider/chess_board_screen_provider_new.dart
+++ b/lib/screens/chessboard/provider/chess_board_screen_provider_new.dart
@@ -776,7 +776,17 @@ class ChessBoardScreenNotifierNew
 
               final newAllMoves = [...currentState.allMoves, extraMove];
               final newMoveSans = [...currentState.moveSans, sanResult.$2];
-              final newMoveTimes = [...currentState.moveTimes, ''];
+              
+              final isWhiteMove = newAllMoves.length % 2 == 1;
+              final clockSeconds = isWhiteMove ? game.whiteClockSeconds : game.blackClockSeconds;
+              final clockCenti = isWhiteMove ? game.whiteClockCentiseconds : game.blackClockCentiseconds;
+              String timeStr = '';
+              if (clockSeconds != null) {
+                timeStr = _formatDisplayTimeFromSeconds(clockSeconds);
+              } else if (clockCenti > 0) {
+                timeStr = _formatDisplayTimeFromSeconds((clockCenti / 100).floor());
+              }
+              final newMoveTimes = [...currentState.moveTimes, timeStr];
 
               final wasViewingLastMove =
                   currentState.currentMoveIndex ==
@@ -1182,7 +1192,18 @@ class ChessBoardScreenNotifierNew
               if (_normalizeFen(candidate.fen) == targetFen) {
                 allMoves.add(extraMove);
                 moveSans.add(sanResult.$2);
-                moveTimes.add('');
+                
+                final isWhiteMove = allMoves.length % 2 == 1;
+                final clockSeconds = isWhiteMove ? game.whiteClockSeconds : game.blackClockSeconds;
+                final clockCenti = isWhiteMove ? game.whiteClockCentiseconds : game.blackClockCentiseconds;
+                String timeStr = '';
+                if (clockSeconds != null) {
+                  timeStr = _formatDisplayTimeFromSeconds(clockSeconds);
+                } else if (clockCenti > 0) {
+                  timeStr = _formatDisplayTimeFromSeconds((clockCenti / 100).floor());
+                }
+                moveTimes.add(timeStr);
+                
                 lastMove = extraMove;
                 finalPos = candidate;
                 lastMoveIndex = allMoves.length - 1;
@@ -1418,6 +1439,7 @@ class ChessBoardScreenNotifierNew
 
     try {
       final game = PgnGame.parsePgn(pgn);
+      final regex = RegExp(r'\[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\]');
 
       // Iterate through the mainline moves
       for (final nodeData in game.moves.mainline()) {
@@ -1427,11 +1449,11 @@ class ChessBoardScreenNotifierNew
         if (nodeData.comments != null) {
           // Extract time if it exists in any comment
           for (String comment in nodeData.comments!) {
-            final timeMatch = RegExp(
-              r'\[%clk (\d+:\d+:\d+)\]',
-            ).firstMatch(comment);
+            final timeMatch = regex.firstMatch(comment);
             if (timeMatch != null) {
-              timeString = timeMatch.group(1);
+              final hours = timeMatch.group(1) ?? '';
+              final rest = timeMatch.group(2) ?? '';
+              timeString = '$hours$rest';
               break; // Found time, no need to check other comments for this move
             }
           }
@@ -1456,17 +1478,31 @@ class ChessBoardScreenNotifierNew
   // Fallback method using the original regex approach
   List<String> _parseMoveTimesFromPgnFallback(String pgn) {
     final List<String> times = [];
-    final regex = RegExp(r'\{ \[%clk (\d+:\d+:\d+)\] \}');
+    final regex = RegExp(r'\{ \[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\] \}');
     final matches = regex.allMatches(pgn);
 
     for (final match in matches) {
-      final timeString = match.group(1) ?? '0:00:00';
-      times.add(_formatDisplayTime(timeString));
+      final hours = match.group(1) ?? '';
+      final rest = match.group(2) ?? '00:00';
+      times.add(_formatDisplayTime('$hours$rest'));
     }
 
     return times;
   }
 
+  String _formatDisplayTimeFromSeconds(int totalSeconds) {
+    if (totalSeconds <= 0) return '0:00';
+    final hours = totalSeconds ~/ 3600;
+    final minutes = (totalSeconds % 3600) ~/ 60;
+    final seconds = totalSeconds % 60;
+    final minStr = minutes.toString().padLeft(2, '0');
+    final secStr = seconds.toString().padLeft(2, '0');
+    if (hours == 0) {
+      return '$minStr:$secStr';
+    }
+    return '$hours:$minStr:$secStr';
+  }
+
   String _formatDisplayTime(String timeString) {
     // Convert "1:40:57" to display format
     final parts = timeString.split(':');
