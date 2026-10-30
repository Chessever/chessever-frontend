import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A cold or warm shared link uses the same reader as both Discovery
/// entrances, without depending on the latest articles being cached.
class NewsLinkScreen extends ConsumerStatefulWidget {
  const NewsLinkScreen({super.key, required this.link});
  final NewsLink link;

  @override
  ConsumerState<NewsLinkScreen> createState() => _NewsLinkScreenState();
}

class _NewsLinkScreenState extends ConsumerState<NewsLinkScreen> {
  late Future<FeedNews?> _article;
  final _heroScope = Object();

  @override
  void initState() {
    super.initState();
    _article = ref.read(newsArticleLoaderProvider)(widget.link);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FeedNews?>(
    future: _article,
    builder: (context, snapshot) {
      if (snapshot.data case final article?) {
        return NewsReaderPager(
          articles: [article],
          initialIndex: 0,
          heroScope: _heroScope,
        );
      }
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: const Text('News')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: snapshot.connectionState != ConnectionState.done
                ? const CircularProgressIndicator(
                    semanticsLabel: 'Loading article',
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.hasError
                            ? "Couldn't load this article."
                            : 'This article is no longer available.',
                        textAlign: TextAlign.center,
                      ),
                      if (snapshot.hasError) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => setState(() {
                            _article = ref.read(newsArticleLoaderProvider)(
                              widget.link,
                            );
                          }),
                          child: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
