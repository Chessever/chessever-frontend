import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

/// watchOS is always dark. Quiet neutral surfaces leave the real chess position
/// and reported scores as the identity; the system face preserves Dynamic Type.
abstract final class WatchStyle {
  static const contentInset = 11.0;
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1B1B1B);
  static const secondary = Color(0xFFB7B7B7);
  static const ink = Color(0xFFF5F5F5);
  static const lightSquare = Color(0xFFBDC4B8);
  static const darkSquare = Color(0xFF596653);
  static const lastMove = Color(0x667F9648);
  static const heading = TextStyle(
    fontFamily: 'CupertinoSystemDisplay',
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: ink,
    height: 1.15,
  );
  static const body = TextStyle(
    fontFamily: 'CupertinoSystemText',
    fontSize: 16,
    color: ink,
    height: 1.25,
  );
  static const caption = TextStyle(
    fontFamily: 'CupertinoSystemText',
    fontSize: 12,
    color: secondary,
    height: 1.3,
  );
}

class WatchPage extends StatelessWidget {
  const WatchPage({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.refreshing = false,
    this.root = false,
    this.boardFirst = false,
    this.boardBackLabel = 'Back to games',
    this.scrollController,
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final bool refreshing;
  final bool root;
  final bool boardFirst;
  final String boardBackLabel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return CupertinoPageScaffold(
      backgroundColor: WatchStyle.background,
      child: _ClockEdge(
        child: WatchCrownScroll(
          child: CustomScrollView(
            controller: scrollController,
            physics: const WatchScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // Native Crown overscroll and finger drags share the same scroll
              // position. The Cupertino control arms beyond the threshold and
              // refreshes once on release, retaining its extent until completion.
              if (onRefresh != null)
                CupertinoSliverRefreshControl(
                  refreshTriggerPullDistance: 52,
                  refreshIndicatorExtent: 32,
                  onRefresh: onRefresh,
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  insets.left + 5,
                  WatchStatusBar.heightOf(context) + 4,
                  insets.right + 5,
                  insets.bottom + 16,
                ),
                sliver: SliverList.list(
                  children: [
                    if (!root && !boardFirst)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: () {
                            WatchHaptics.click();
                            Navigator.of(context).maybePop();
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.chevron_back,
                                size: 18,
                                color: WatchStyle.ink,
                              ),
                              SizedBox(width: 4),
                              Text('Back', style: WatchStyle.body),
                            ],
                          ),
                        ),
                      ),
                    if (!boardFirst)
                      Semantics(
                        header: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            WatchStyle.contentInset,
                            0,
                            WatchStyle.contentInset,
                            12,
                          ),
                          child: Text(title, style: WatchStyle.heading),
                        ),
                      ),
                    ...children,
                    if (boardFirst)
                      WatchRow(
                        label: boardBackLabel,
                        showChevron: false,
                        icon: CupertinoIcons.chevron_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    if (onRefresh != null)
                      WatchRow(
                        label: 'Refresh',
                        showChevron: false,
                        icon: CupertinoIcons.refresh,
                        onTap: refreshing ? null : onRefresh,
                        trailing: refreshing
                            ? const CupertinoActivityIndicator(radius: 7)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// watchOS fades a list out under the system clock as it scrolls; without
/// it a row runs straight into the time. The page is pure black, so a black
/// veil over the band reads as the content fading. At
/// rest it is invisible: the band row (mark or back chevron) stays crisp.
class _ClockEdge extends StatefulWidget {
  const _ClockEdge({required this.child});
  final Widget child;
  @override
  State<_ClockEdge> createState() => _ClockEdgeState();
}

class _ClockEdgeState extends State<_ClockEdge> {
  final _scrolled = ValueNotifier<double>(0);
  double _nextStrength = 0;
  bool _queued = false;

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final band = WatchStatusBar.heightOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          final pixels = notification.metrics.pixels;
          _nextStrength = (pixels / math.max(band, 1)).clamp(0.0, 1.0);
          // Refresh slivers may correct their extent during layout. Update
          // the veil after that frame, rather than rebuilding during layout.
          if (!_queued) {
            _queued = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _queued = false;
              if (mounted) _scrolled.value = _nextStrength;
            });
          }
        }
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: band,
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _scrolled,
                builder: (context, strength, _) => strength == 0
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: strength,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                WatchStyle.background,
                                WatchStyle.background,
                                Color(0x00000000),
                              ],
                              stops: [0, 0.62, 1],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WatchRow extends StatelessWidget {
  const WatchRow({
    super.key,
    required this.label,
    this.detail,
    this.trailing,
    this.visual,
    this.icon,
    this.onTap,
    this.semanticLabel,
    this.showChevron = true,
  });
  final String label;
  final String? detail;
  final Widget? trailing;
  final Widget? visual;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final accessory =
        trailing ??
        (onTap == null || !showChevron
            ? null
            : const Icon(
                CupertinoIcons.chevron_forward,
                size: 13,
                color: WatchStyle.secondary,
              ));
    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(WatchStyle.contentInset),
      decoration: BoxDecoration(
        color: WatchStyle.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: WatchStyle.secondary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WatchRowLabel(label),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (visual != null) ...[
                        ExcludeSemantics(child: visual!),
                        const SizedBox(width: 6),
                      ],
                      Expanded(child: Text(detail!, style: WatchStyle.caption)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (accessory != null) ...[const SizedBox(width: 6), accessory],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: onTap == null
          ? content
          : Semantics(
              label: semanticLabel,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () {
                  WatchHaptics.click();
                  onTap!();
                },
                child: content,
              ),
            ),
    );
  }
}

/// Fit only an overlong word, retaining normal wrapping and Dynamic Type.
class _WatchRowLabel extends StatelessWidget {
  const _WatchRowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.split(RegExp(r'\s+')).join('\n'),
          style: WatchStyle.body,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final widest = painter.width;
      painter.dispose();
      final size = widest > constraints.maxWidth
          ? (16 * constraints.maxWidth / widest).clamp(13.0, 16.0)
          : 16.0;
      return Text(text, style: WatchStyle.body.copyWith(fontSize: size));
    },
  );
}

class WatchNote extends StatelessWidget {
  const WatchNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WatchStyle.contentInset,
      6,
      WatchStyle.contentInset,
      12,
    ),
    child: Text(text, style: WatchStyle.caption),
  );
}

void watchPush(BuildContext context, Widget page) =>
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));

/// Reusable data screen. Keeps real data on transient failures, makes retries
/// explicit, and only offers another page when the preceding one was full.
class WatchDataPage<T> extends StatefulWidget {
  const WatchDataPage({
    super.key,
    required this.title,
    required this.load,
    required this.items,
    this.pageSize,
    this.empty = 'Nothing here yet.',
  });
  final String title;
  final Future<List<T>> Function(int offset) load;
  final List<Widget> Function(BuildContext context, List<T> data) items;
  final int? pageSize;
  final String empty;
  @override
  State<WatchDataPage<T>> createState() => _WatchDataPageState<T>();
}

class _WatchDataPageState<T> extends State<WatchDataPage<T>> {
  List<T> _data = [];
  bool _busy = false;
  bool _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.load(more ? _data.length : 0);
      if (!mounted) return;
      setState(() {
        _data = more ? [..._data, ...page] : page;
        _more = widget.pageSize != null && page.length == widget.pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WatchPage(
    title: widget.title,
    onRefresh: () => _load(),
    refreshing: _busy,
    children: [
      if (_busy && _data.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      if (_error != null) WatchNote(_error!),
      if (!_busy && _error == null && _data.isEmpty) WatchNote(widget.empty),
      ...widget.items(context, _data),
      if (_more && !_busy)
        WatchRow(label: 'Load more', onTap: () => _load(more: true)),
    ],
  );
}
