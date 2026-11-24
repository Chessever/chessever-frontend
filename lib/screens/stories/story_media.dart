import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/stories/story_publications.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class StoryLayerSurface extends StatelessWidget {
  const StoryLayerSurface({
    super.key,
    required this.layers,
    required this.child,
    this.onOpen,
  });

  final List<StoryLayer> layers;
  final Widget child;
  final ValueChanged<Uri>? onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, area) {
        final width = area.maxWidth;
        final height = area.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(child: child),
            Positioned.fill(
              left: width * .05,
              right: width * .05,
              top: height * .05,
              bottom: height * .12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final layer in layers)
                    Align(
                      alignment: Alignment(layer.x * 2 - 1, layer.y * 2 - 1),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: width * .77),
                        child: _StoryLayerLabel(layer: layer, onOpen: onOpen),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StoryLayerLabel extends StatelessWidget {
  const _StoryLayerLabel({required this.layer, this.onOpen});

  final StoryLayer layer;
  final ValueChanged<Uri>? onOpen;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (layer.tone) {
      'dark' => (const Color(0xff25281f), const Color(0xfff2f1e7)),
      'accent' => (const Color(0xff18251a), const Color(0xffc6dbbc)),
      _ => (const Color(0xfff5f6ee), const Color(0xe6171a17)),
    };
    final emoji = layer.kind == 'emoji';
    final size = switch (layer.size) {
      'small' => emoji ? 30.0 : 16.0,
      'large' => emoji ? 62.0 : 28.0,
      _ => emoji ? 46.0 : 21.0,
    };
    final text = Text(
      layer.text,
      textAlign: TextAlign.center,
      style: AppTypography.textSmBold.copyWith(
        color: foreground,
        fontSize: size,
        height: 1.15,
      ),
    );
    final link = layer.link;
    if (link != null && onOpen != null) {
      return TextButton.icon(
        onPressed: () => onOpen?.call(link),
        icon: const Icon(Icons.link, size: 18),
        label: text,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: emoji ? Colors.transparent : background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: emoji
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: text,
        ),
      ),
    );
  }
}

class StoryMediaImage extends StatelessWidget {
  const StoryMediaImage({super.key, required this.media});

  final StoryEditorialMedia media;

  @override
  Widget build(BuildContext context) {
    final url = media.imageUrl;
    if (url == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final decodeWidth =
            (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(1, 1440);
        return Semantics(
          image: true,
          label: media.alt ?? (media.title.isEmpty ? null : media.title),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            memCacheWidth: decodeWidth,
            fadeInDuration: Duration.zero,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class PublishedStoryMedia extends StatelessWidget {
  const PublishedStoryMedia({super.key, required this.media, this.onTouch});

  final StoryEditorialMedia media;
  final ValueChanged<int>? onTouch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = media.title;
    final body = media.body;
    return Listener(
      onPointerDown: (event) => onTouch?.call(event.pointer),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (media.imageUrl != null) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.52,
                  ),
                  child: StoryMediaImage(media: media),
                ),
                if (title.isNotEmpty || body != null)
                  const SizedBox(height: 16),
              ],
              if (title.isNotEmpty)
                Text(
                  title,
                  style: AppTypography.textXlBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              if (body != null) ...[
                if (title.isNotEmpty) const SizedBox(height: 8),
                Text(
                  body,
                  style: AppTypography.textSmRegular.copyWith(
                    color: colors.textPrimaryMuted,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StoryMediaCaption extends StatelessWidget {
  const StoryMediaCaption({super.key, required this.media, this.onTouch});

  final StoryEditorialMedia media;
  final ValueChanged<int>? onTouch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .18,
      ),
      child: Listener(
        onPointerDown: (event) => onTouch?.call(event.pointer),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (media.title.isNotEmpty)
                Text(
                  media.title,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              if (media.body case final body?)
                Text(
                  body,
                  style: AppTypography.textSmRegular.copyWith(
                    color: colors.textPrimaryMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
