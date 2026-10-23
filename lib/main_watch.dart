import 'package:flutter/widgets.dart';
import 'watch/watch_app.dart';

/// Use --target lib/main_watch.dart for the small watch snapshot. Phone startup,
/// analytics, purchases, ads, database, and Stockfish are not reachable here.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChessEverWatchApp());
}
