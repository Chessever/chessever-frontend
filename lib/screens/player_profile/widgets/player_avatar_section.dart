import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Section displaying player avatar with three rating cards (Classical, Rapid, Blitz).
class PlayerAvatarSection extends StatefulWidget {
  const PlayerAvatarSection({
    super.key,
    required this.fideId,
    required this.playerName,
    this.classicalRating,
    this.rapidRating,
    this.blitzRating,
  });

  final String? fideId;
  final String playerName;
  final int? classicalRating;
  final int? rapidRating;
  final int? blitzRating;

  @override
  State<PlayerAvatarSection> createState() => _PlayerAvatarSectionState();
}

class _PlayerAvatarSectionState extends State<PlayerAvatarSection> {
  Future<String?>? _photoFuture;

  @override
  void initState() {
    super.initState();
    _photoFuture = _loadPhoto(widget.fideId);
  }

  @override
  void didUpdateWidget(covariant PlayerAvatarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fideId != widget.fideId) {
      _photoFuture = _loadPhoto(widget.fideId);
    }
  }

  Future<String?> _loadPhoto(String? fideId) {
    if (fideId == null || fideId.isEmpty) return Future.value(null);
    return FidePhotoService.getPhotoUrlOrNull(fideId);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPlayerAvatar(),
        SizedBox(width: 16.w),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildRatingCard(
                  icon: PngAsset.classicalIcon,
                  label: 'Classical',
                  rating: widget.classicalRating,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _buildRatingCard(
                  icon: PngAsset.rapidIcon,
                  label: 'Rapid',
                  rating: widget.rapidRating,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _buildRatingCard(
                  icon: PngAsset.blitzIcon,
                  label: 'Blitz',
                  rating: widget.blitzRating,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerAvatar() {
    final initials = _getInitials(widget.playerName);

    return FutureBuilder<String?>(
      future: _photoFuture,
      builder: (context, snapshot) {
        final photoUrl = snapshot.data;

        return Container(
          width: 110.w,
          height: 110.w,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.br),
            color: kBlack2Color,
          ),
          clipBehavior: Clip.antiAlias,
          child:
              photoUrl != null
                  ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    placeholder:
                        (context, url) => _buildInitialsPlaceholder(initials),
                    errorWidget:
                        (context, url, error) =>
                            _buildInitialsPlaceholder(initials),
                  )
                  : _buildInitialsPlaceholder(initials),
        );
      },
    );
  }

  Widget _buildInitialsPlaceholder(String initials) {
    return Container(
      decoration: const BoxDecoration(gradient: kProfileInitialsGradient),
      child: Center(
        child: Text(
          initials,
          style: AppTypography.textXlBold.copyWith(color: kWhiteColor),
        ),
      ),
    );
  }

  Widget _buildRatingCard({
    required String icon,
    required String label,
    required int? rating,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(icon, width: 18.w, height: 18.h),
              SizedBox(width: 8.w),
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: kWhiteColor70,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            rating?.toString() ?? '-',
            style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(', ');
    if (parts.length >= 2) {
      // Format: "Lastname, Firstname" -> "FL"
      return '${parts[1][0]}${parts[0][0]}'.toUpperCase();
    }
    // Fallback: first two characters
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : name.length).toUpperCase();
  }
}
