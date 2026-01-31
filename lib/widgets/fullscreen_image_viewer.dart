import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

/// Shows a fullscreen player avatar image with smooth heroine transition.
/// If no photo URL is provided, shows the initials placeholder.
void showPlayerAvatarFullscreen({
  required BuildContext context,
  required String? photoUrl,
  required String initials,
  required String heroTag,
  String? title,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenPlayerAvatar(
          photoUrl: photoUrl,
          initials: initials,
          heroTag: heroTag,
          title: title,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    ),
  );
}

class _FullscreenPlayerAvatar extends StatelessWidget {
  const _FullscreenPlayerAvatar({
    required this.photoUrl,
    required this.initials,
    required this.heroTag,
    this.title,
  });

  final String? photoUrl;
  final String initials;
  final String heroTag;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final screenSize = MediaQuery.of(context).size;
    final imageSize = screenSize.width * 0.85;

    return DragDismissable.custom(
      onDismiss: () => Navigator.of(context).pop(),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Heroine(
              tag: heroTag,
              motion: const CupertinoMotion.smooth(),
              flightShuttleBuilder: const FadeShuttleBuilder(),
              child: Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.br),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24.br),
                  child: hasPhoto
                      ? CachedNetworkImage(
                          imageUrl: photoUrl!,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _InitialsDisplay(
                            initials: initials,
                            size: imageSize,
                            title: title,
                          ),
                          errorWidget: (context, url, error) => _InitialsDisplay(
                            initials: initials,
                            size: imageSize,
                            title: title,
                          ),
                        )
                      : _InitialsDisplay(
                          initials: initials,
                          size: imageSize,
                          title: title,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialsDisplay extends StatelessWidget {
  const _InitialsDisplay({
    required this.initials,
    required this.size,
    this.title,
  });

  final String initials;
  final double size;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.3;
    final effectiveInitials = initials.isNotEmpty ? initials.toUpperCase() : '?';

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            gradient: kProfileInitialsGradient,
          ),
          child: Center(
            child: Text(
              effectiveInitials,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
        if (title != null && title!.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: getTitleBadgeColor(title!),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(22.br),
                  bottomRight: Radius.circular(22.br),
                ),
              ),
              child: Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
