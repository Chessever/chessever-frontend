import 'package:chessever2/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    return SizedBox(
      height: height,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.fitHeight,
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
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: height,
                      width: double.infinity,
                      color: kDarkGreyColor,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: kWhiteColor,
                        size: 50,
                      ),
                    );
                  },
                ),
              ),
            ),
        errorWidget:
            (context, url, error) => Container(
              height: height,
              width: double.infinity,
              decoration: const BoxDecoration(color: kDarkGreyColor),
              child: Image.asset(
                placeHolder,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: height,
                    width: double.infinity,
                    color: kDarkGreyColor,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: kWhiteColor,
                      size: 50,
                    ),
                  );
                },
              ),
            ),
      ),
    );
  }
}
