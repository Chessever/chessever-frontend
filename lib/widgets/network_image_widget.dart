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
    return Image.network(
      imageUrl,
      height: height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Center(
          child: CircularProgressIndicator(
            value:
                loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(placeHolder, fit: BoxFit.cover);
      },
      fit: BoxFit.cover,
    );
  }
}
