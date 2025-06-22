import 'package:chessever2/theme/app_theme.dart';
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
      child: Image.network(
        imageUrl,
        height: height,
        width: double.infinity,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return Container(
            height: height,
            alignment: Alignment.center,
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: kDarkGreyColor,
            ),
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
          );
        },
      ),
    );
  }
}