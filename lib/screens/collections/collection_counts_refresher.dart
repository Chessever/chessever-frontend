import 'dart:async';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Keeps the view and star counts under [child] current while it is the page
/// on screen: once when it appears, then on a short beat, and again when the
/// app returns. Off screen (another tab, a page pushed over it, the app in
/// the background) it asks for nothing.
class CollectionCountsRefresher extends ConsumerStatefulWidget {
  const CollectionCountsRefresher({super.key, required this.child});

  static const Duration interval = Duration(seconds: 20);

  final Widget child;

  @override
  ConsumerState<CollectionCountsRefresher> createState() =>
      _CollectionCountsRefresherState();
}

class _CollectionCountsRefresherState
    extends ConsumerState<CollectionCountsRefresher>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(
      CollectionCountsRefresher.interval,
      (_) => _refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(ref.read(collectionEngagementProvider).refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
