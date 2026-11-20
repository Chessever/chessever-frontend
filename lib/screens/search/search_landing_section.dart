import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryType, discoveryType;
import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_page_sections.dart'
    show searchHeadingGap, searchPageGutter, searchSectionGap;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';

/// A landing section's head: its title as a button (the heading's own type,
/// a chevron after it) that opens the section's own page. On the page's
/// gutter, 44 tall.
class SearchSectionHeading extends StatelessWidget {
  const SearchSectionHeading({
    super.key,
    required this.title,
    required this.onOpen,
    this.buttonKey,
  });

  final String title;
  final VoidCallback onOpen;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: searchPageGutter),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(44.0, 44.w)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SearchSectionTitleButton(
            key: buttonKey,
            title: title,
            onOpen: onOpen,
          ),
        ),
      ),
    );
  }
}

/// A section's title as the way to its page: the words in the section
/// heading's type, a chevron after them in quiet ink, centred on the words'
/// line. A 44pt target that goes down under the finger; heard as "Open
/// <title>", a heading and a button.
class SearchSectionTitleButton extends StatelessWidget {
  const SearchSectionTitleButton({
    super.key,
    required this.title,
    required this.onOpen,
  });

  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final style = discoveryType(context, DiscoveryType.title);
    final glyph =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 17) * 1.15;
    void open() {
      HapticFeedbackService.navigation();
      onOpen();
    }

    final target = math.max(44.0, 44.w);
    return Semantics(
      container: true,
      header: true,
      button: true,
      label: 'Open $title',
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: PressSpring(
          pressedScale: 0.97,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: target, minWidth: target),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                SizedBox(width: 2.w),
                Icon(
                  Icons.chevron_right_rounded,
                  size: glyph,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One section of the landing: its head ([SearchSectionHeading], the title
/// opening the section's own page through [onOpen]), then its cards in a
/// row ([SearchCarousel]), read on as the reader scrolls it and ending in
/// its See more card (that page again). Nothing sits under the row: the
/// next section begins a section's gap ([searchSectionGap]) below it.
class SearchLandingSection<T> extends StatelessWidget {
  const SearchLandingSection({
    super.key,
    required this.id,
    required this.title,
    required this.items,
    required this.card,
    required this.sizing,
    required this.onOpen,
    this.pending = 0,
    this.hasMore = false,
    this.loading = false,
    this.failed = false,
    this.onLoadMore,
    this.onRetry,
  });

  /// Names the section's keys (`search-<id>-open`) and its row's
  /// ([SearchCarousel.section]).
  final String id;
  final String title;
  final List<T> items;

  /// The card of [items] at an index.
  final Widget Function(BuildContext context, T item, int index) card;
  final SearchCarouselSizing sizing;
  final VoidCallback onOpen;
  final int pending;
  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SearchSectionHeading(
            buttonKey: ValueKey('search-$id-open'),
            title: title,
            onOpen: onOpen,
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: searchHeadingGap),
              SearchCarousel(
                section: id,
                title: title,
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    card(context, items[index], index),
                sizing: sizing,
                onSeeMore: onOpen,
                pending: pending,
                hasMore: hasMore,
                loading: loading,
                failed: failed,
                onLoadMore: onLoadMore,
                onRetry: onRetry,
              ),
              SizedBox(height: searchSectionGap),
            ],
          ),
        ),
      ],
    );
  }
}
