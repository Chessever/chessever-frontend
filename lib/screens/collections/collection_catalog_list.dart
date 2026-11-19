import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart'
    show EventViewSearchButtonGap, EventViewSearchList, EventViewSearchPlace;
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';

class CatalogBatch<T> {
  const CatalogBatch(this.items, this.total);
  final List<T> items;
  final int total;
}

/// The rows a catalog held for one query, kept to come back to.
class _CatalogRows<T> {
  const _CatalogRows(this.query, this.items, this.offset, this.more);
  final CollectionSearchQuery query;
  final List<T> items;
  final int offset;
  final bool more;
}

/// Fetches near the bottom, retains rows on a failed next page, and ignores
/// replies from an old query. No full-catalog download or device-side filtering.
///
/// Searched in place, as every Games list is: a new query loads over the
/// rows on screen (the same list, under the search's quiet progress line)
/// and its first page takes their place at the list's top; once the words
/// are gone, the list from before them is back at once, where the reader
/// left it, with no request and no spinner. It ends with the shell's
/// [EventViewSearchButtonGap].
class CollectionCatalogList<T> extends StatefulWidget {
  const CollectionCatalogList({
    super.key,
    required this.query,
    required this.load,
    this.itemBuilder,
    this.indexedItemBuilder,
    required this.identity,
    required this.padding,
    required this.emptyMessage,
    this.compare,
    this.subject = 'collections',
    this.onClear,
  }) : assert(itemBuilder != null || indexedItemBuilder != null);
  final CollectionSearchQuery query;
  final Future<CatalogBatch<T>> Function(int offset) load;
  final Widget Function(T item)? itemBuilder;

  /// Index in the displayed list, including rows loaded on earlier pages.
  final Widget Function(T item, int index)? indexedItemBuilder;
  final String Function(T item) identity;
  final EdgeInsets padding;
  final String emptyMessage;
  final Comparator<T>? compare;

  /// What the list holds, plural, for its no-hits line ([SearchNoMatches]).
  final String subject;

  /// The no-hits line's way back: clears the words when the query has any,
  /// else its filters. Null offers none.
  final VoidCallback? onClear;
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

  /// The failed request was a first page: trying again starts over.
  bool _failedFirstPage = false;

  /// A first page is on its way; the rows on screen stay until it lands.
  bool _resetting = false;

  /// A first page has landed: later ones load over the rows.
  bool _answered = false;

  /// The query the rows on screen answer.
  CollectionSearchQuery? _rowsQuery;

  /// The list as it stood before words were searched, back once they go.
  _CatalogRows<T>? _beforeWords;

  final EventViewSearchPlace _place = EventViewSearchPlace();

  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  static bool _hasWords(CollectionSearchQuery query) =>
      query.text.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant CollectionCatalogList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query == oldWidget.query) return;
    final words = _hasWords(widget.query);
    if (!_hasWords(oldWidget.query) && words) {
      // Kept only whole: not while it was itself still loading, nor a
      // failed first page.
      final whole =
          _answered &&
          !_resetting &&
          _rowsQuery == oldWidget.query &&
          !(_error != null && _failedFirstPage);
      _beforeWords = whole
          ? _CatalogRows(oldWidget.query, List.of(_items), _offset, _more)
          : null;
    }
    // Asked while the list still shows the rows it showed.
    _place.queryChanged(context, widget.query.text);
    final before = words ? null : _beforeWords;
    if (!words) _beforeWords = null;
    if (before != null && before.query == widget.query) {
      _restore(before);
      return;
    }
    // Not the list that was left (the filters changed under the words, or
    // it had not loaded whole): another list, read from its top.
    if (!words) _place.forget();
    _load(reset: true);
  }

  /// [rows] on screen again, as they were: replies still on their way for
  /// the words are dropped.
  void _restore(_CatalogRows<T> rows) {
    _generation++;
    _items
      ..clear()
      ..addAll(rows.items);
    _rowsQuery = rows.query;
    _offset = rows.offset;
    _more = rows.more;
    _loading = false;
    _resetting = false;
    _error = null;
    _failedFirstPage = false;
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    final generation = reset ? ++_generation : _generation;
    final asked = widget.query;
    setState(() {
      if (reset) _resetting = true;
      _loading = true;
      _error = null;
    });
    try {
      final batch = await widget.load(reset ? 0 : _offset);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) {
          // The first page takes the place of the rows it loaded over.
          _items.clear();
          _offset = 0;
          _rowsQuery = asked;
          _resetting = false;
          _answered = true;
        }
        final seen = _items.map(widget.identity).toSet();
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
        _failedFirstPage = reset;
        if (reset) {
          _resetting = false;
          // A query that failed says so, rather than leaving the last
          // query's rows up as if they answered it. A refresh keeps them.
          if (_rowsQuery != asked) {
            _items.clear();
            _offset = 0;
            _more = true;
            _rowsQuery = asked;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // The rows for what was asked are in hand: they are laid out in their
    // place (the top for new results, the reader's own once words go).
    if (!_resetting) _place.settle(context);
    // Another query's first page on its way over these rows (a pull to
    // refresh has its own indicator).
    final replacing = _resetting && _answered && _rowsQuery != widget.query;
    final ranked = _items.indexed.toList();
    if (widget.compare case final compare?) {
      ranked.sort((a, b) {
        final rank = compare(a.$2, b.$2);
        return rank == 0 ? a.$1.compareTo(b.$1) : rank;
      });
    }
    final rows = ranked.map((entry) => entry.$2).toList();
    // A search that left nothing says so on the list's own gutter, where
    // its first row would be ([SearchNoMatches] keeps that edge itself).
    final noHits = _noHits;
    return EventViewSearchList(
      busy: replacing,
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notice) {
            if (notice.metrics.extentAfter < 600 && _error == null) _load();
            return false;
          },
          // One list for every query: it is never rebuilt for a new one.
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: noHits
                ? EdgeInsets.only(bottom: widget.padding.bottom)
                : widget.padding,
            itemCount: rows.length + 2,
            itemBuilder: (context, index) {
              if (index < rows.length) {
                return widget.indexedItemBuilder?.call(rows[index], index) ??
                    widget.itemBuilder!(rows[index]);
              }
              if (index > rows.length) return const EventViewSearchButtonGap();
              return _footer();
            },
          ),
        ),
      ),
    );
  }

  /// The answered query left no row: words or filters narrowed it to
  /// nothing.
  bool get _noHits =>
      _items.isEmpty &&
      !_loading &&
      _error == null &&
      !(_resetting && _answered) &&
      widget.query.isActive;

  /// After the last row: the next page loading, an error, or the empty
  /// list's message.
  Widget _footer() {
    // A first page on its way over rows already shown: the line along the
    // top (or the pull's own indicator) says so.
    if (_resetting && _answered) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return Column(
        children: [
          Text(
            userFacingError(
              error,
              fallback:
                  error is CollectionsRequestException &&
                      error.statusCode == 400
                  ? 'Check your search. Use an ECO code such as B20 or a tag like [White "Carlsen"].'
                  : "Couldn't load collections.",
            ),
          ),
          TextButton(
            onPressed: () => _load(reset: _failedFirstPage),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    if (_items.isEmpty && widget.query.isActive) {
      final words = widget.query.text.trim();
      return SearchNoMatches(
        key: const ValueKey('collection_catalog_no_matches'),
        query: words,
        subject: widget.subject,
        filtered: words.isEmpty,
        onClear: widget.onClear,
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(widget.emptyMessage, textAlign: TextAlign.center),
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
  }
}
