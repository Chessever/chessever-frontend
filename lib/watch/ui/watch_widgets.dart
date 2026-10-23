import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

/// watchOS is always dark. Quiet neutral surfaces leave the real chess position
/// and reported scores as the identity; the system face preserves Dynamic Type.
abstract final class WatchStyle {
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
    this.root = false,
    this.boardFirst = false,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onRefresh;
  final bool root;
  final bool boardFirst;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return CupertinoPageScaffold(
      backgroundColor: WatchStyle.background,
      child: WatchCrownScroll(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            insets.left + 5,
            WatchStatusBar.heightOf(context) + 4,
            insets.right + 5,
            insets.bottom + 16,
          ),
          children: [
            if (!root && !boardFirst)
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => Navigator.of(context).maybePop(),
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(title, style: WatchStyle.heading),
                ),
              ),
            ...children,
            if (boardFirst)
              WatchRow(
                label: 'Back to games',
                icon: CupertinoIcons.chevron_back,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            if (onRefresh != null)
              WatchRow(
                label: 'Refresh',
                icon: CupertinoIcons.refresh,
                onTap: onRefresh,
              ),
          ],
        ),
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
    this.icon,
    this.onTap,
    this.semanticLabel,
  });
  final String label;
  final String? detail;
  final Widget? trailing;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final accessory =
        trailing ??
        (onTap == null
            ? null
            : const Icon(
                CupertinoIcons.chevron_forward,
                size: 13,
                color: WatchStyle.secondary,
              ));
    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
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
                if (detail != null)
                  Text(label, style: WatchStyle.body)
                else
                  Row(
                    children: [
                      Expanded(child: Text(label, style: WatchStyle.body)),
                      if (accessory != null) ...[
                        const SizedBox(width: 6),
                        accessory,
                      ],
                    ],
                  ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: Text(detail!, style: WatchStyle.caption)),
                      if (accessory != null) ...[
                        const SizedBox(width: 6),
                        accessory,
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
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

class WatchNote extends StatelessWidget {
  const WatchNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
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
    onRefresh: _busy ? null : () => _load(),
    children: [
      if (_busy)
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
