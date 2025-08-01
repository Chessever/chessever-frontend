import 'package:chessever2/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
        fit: BoxFit.contain,
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
                fit: BoxFit.contain, // Optional: specify how the image should fit
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
                ),
              ),
            ),
        errorWidget:
            (context, url, error) => ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Container(
                height: height,
                width: double.infinity,
                color: kDarkGreyColor,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_not_supported,
                  color: kWhiteColor,
                  size: 50,
                ),
              ),
            ),
      ),
    );
  }
}
