import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_group_repository.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class NewsRelatedArticles extends ConsumerStatefulWidget {
  const NewsRelatedArticles({super.key, required this.articleId});
  final int articleId;

  @override
  ConsumerState<NewsRelatedArticles> createState() =>
      _NewsRelatedArticlesState();
}

class _NewsRelatedArticlesState extends ConsumerState<NewsRelatedArticles> {
  final _items = <NewsGroupArticle>[];
  bool _loading = true;
  bool _failed = false;
  bool _more = false;
  int? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(newsGroupRepositoryProvider)
          .load(widget.articleId, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _more = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(NewsGroupArticle item) async {
    if (_opening != null) return;
    setState(() => _opening = item.id);
    try {
      final article = await ref.read(newsArticleLoaderProvider)(
        NewsLink(id: item.id),
      );
      if (!mounted) return;
      if (article == null) throw StateError('Article is no longer published');
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: Uri.parse(newsShareUrl(article)).path),
          builder: (_) =>
              NewsReaderScreen(news: article, showRelatedArticles: false),
        ),
      );
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          "Couldn't open article. Try again.",
          tone: AppSnackTone.danger,
          actionLabel: 'Retry',
          onAction: () => _open(item),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && !_failed && _items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Related articles',
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in _items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(
                DateFormat(
                  'MMM d, y · h:mm a',
                ).format(item.publishedAt.toLocal()),
              ),
              trailing: _opening == item.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              enabled: _opening == null,
              onTap: () => _open(item),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            TextButton(
              onPressed: _load,
              child: const Text("Couldn't load related articles. Retry"),
            )
          else if (_more)
            TextButton(onPressed: _load, child: const Text('Show more')),
        ],
      ),
    );
  }
}
