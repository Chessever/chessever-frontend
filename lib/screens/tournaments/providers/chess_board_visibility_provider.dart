import 'package:hooks_riverpod/hooks_riverpod.dart';

final chessBoardVisibilityProvider = AutoDisposeStateProvider<bool>(
  (ref) => false,
);
