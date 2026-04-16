import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/logo_pattern_fallback.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';

class NetworkImageWidget extends StatelessWidget {
  const NetworkImageWidget({
    required this.imageUrl,
    required this.height,
    required this.placeHolder,
    super.key,
  });

  final String imageUrl;
  final double height;
  final String placeHolder;

  @override
  Widget build(BuildContext context) {
    final cacheHeight =
        (height * MediaQuery.devicePixelRatioOf(context)).toInt();

    return SizedBox(
      height: height,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.contain,
        memCacheHeight: cacheHeight,
        imageBuilder: (context, imageProvider) {
          return Container(
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16.br),
                topRight: Radius.circular(16.br),
              ),
              image: DecorationImage(
                alignment: Alignment.topCenter,
                image: imageProvider,
                fit:
                    BoxFit
                        .contain, // Optional: specify how the image should fit
              ),
            ),
          );
        },
        placeholder:
            (context, url) => SkeletonWidget(
              child: Container(
                height: height,
                alignment: Alignment.center,
                child: Image.asset(
                  placeHolder,
                  height: height,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheHeight: cacheHeight,
                ),
              ),
            ),
        errorWidget:
            (context, url, error) => SizedBox(
              height: height,
              width: double.infinity,
              child: LogoPatternFallback(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.br),
                  topRight: Radius.circular(16.br),
                ),
              ),
            ),
      ),
    );
  }
}
