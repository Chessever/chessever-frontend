import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shared by My Space and its floating menu. Selection stays in the page.
final spaceEditModeProvider = StateProvider.autoDispose<bool>((ref) => false);
