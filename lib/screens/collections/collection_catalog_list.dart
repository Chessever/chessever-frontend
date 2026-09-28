import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:flutter/material.dart';

class CatalogBatch<T> {
  const CatalogBatch(this.items, this.total);
  final List<T> items;
  final int total;
}

/// Fetches near the bottom, retains rows on a failed next page, and ignores
/// replies from an old query. No full-catalog download or device-side filtering.
class CollectionCatalogList<T> extends StatefulWidget {
  const CollectionCatalogList({
    super.key,
    required this.query,
    required this.load,
    required this.itemBuilder,
    required this.identity,
    required this.padding,
    required this.emptyMessage,
  });
  final CollectionSearchQuery query;
  final Future<CatalogBatch<T>> Function(int offset) load;
  final Widget Function(T item) itemBuilder;
  final String Function(T item) identity;
  final EdgeInsets padding;
  final String emptyMessage;
  @override
  State<CollectionCatalogList<T>> createState() =>
      _CollectionCatalogListState<T>();
}

class _CollectionCatalogListState<T> extends State<CollectionCatalogList<T>>
    with AutomaticKeepAliveClientMixin {
  final _items = <T>[];
  int _generation = 0, _offset = 0;
  bool _loading = false, _more = true;
  Object? _error;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant CollectionCatalogList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) {
      _load(reset: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = PrimaryScrollController.maybeOf(context);
        if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
      });
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) {
        _items.clear();
        _offset = 0;
        _more = true;
      }
      _loading = true;
      _error = null;
    });
    try {
      final batch = await widget.load(_offset);
      if (!mounted || generation != _generation) return;
      final seen = _items.map(widget.identity).toSet();
      setState(() {
        _items.addAll(
          batch.items.where((item) => seen.add(widget.identity(item))),
        );
        _offset += batch.items.length;
        _more = batch.items.isNotEmpty && _offset < batch.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.metrics.extentAfter < 600 && _error == null) _load();
          return false;
        },
        child: ListView.builder(
          key: ValueKey(widget.query),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          itemCount: _items.length + 1,
          itemBuilder: (context, index) {
            if (index < _items.length) return widget.itemBuilder(_items[index]);
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_error != null) {
              return Column(
                children: [
                  Text(
                    userFacingError(
                      _error,
                      fallback:
                          _error is CollectionsRequestException &&
                              (_error as CollectionsRequestException)
                                      .statusCode ==
                                  400
                          ? 'Check your search. Use an ECO code such as B20 or a tag like [White "Carlsen"].'
                          : "Couldn't load collections.",
                    ),
                  ),
                  TextButton(
                    onPressed: () => _load(),
                    child: const Text('Try again'),
                  ),
                ],
              );
            }
            if (_items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.query.isActive
                      ? 'No matches. Try another search or clear filters.'
                      : widget.emptyMessage,
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (_more) {
              // Also handles a short page which has not filled the viewport yet.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _error == null) _load();
              });
              return const SizedBox(height: 48);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
