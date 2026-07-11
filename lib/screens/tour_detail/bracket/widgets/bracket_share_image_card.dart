import 'dart:typed_data';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

/// Branded frame around a live snapshot of the knockout bracket canvas.
///
/// The [snapshot] is the raw viewport capture the user framed by panning/zooming
/// the bracket (see `captureBoundaryPng` + `bracketShareBoundaryKeyProvider`).
/// This card wraps it in the same ChessEver header/footer chrome as the other
/// share images so the shared artifact is on-brand and X/Twitter-sized. Rendered
/// off-screen via `captureCardPng`.
class BracketShareImageCard extends StatelessWidget {
  const BracketShareImageCard({
    super.key,
    required this.width,
    required this.eventName,
    required this.snapshot,
    required this.snapshotAspectRatio,
  });

  final double width;
  final String? eventName;
  final Uint8List snapshot;

  /// Snapshot width / height, so the framed image keeps its captured proportions
  /// (no stretch). Falls back to a portrait ratio when non-finite.
  final double snapshotAspectRatio;

  static const _bg = Color(0xFF0A0B0D);
  static const _hairline = Color(0xFF23262E);
  static const _cyan = kPrimaryColor;
  static const _textHi = Colors.white;
  static const _textLo = Color(0xFF868C97);
  static const _padH = 22.0;

  @override
  Widget build(BuildContext context) {
    final ratio =
        snapshotAspectRatio.isFinite && snapshotAspectRatio > 0
            ? snapshotAspectRatio
            : 3 / 4;

    return MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: _bg,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 4, _padH, 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _hairline),
                      ),
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: Image.memory(
                          snapshot,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = eventName?.trim();
    final hasEvent = title != null && title.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(_cyan.withValues(alpha: 0.13), _bg), _bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _logoBadge(26),
                const SizedBox(width: 9),
                Text(
                  'ChessEver',
                  style: AppTypography.textSmBold.copyWith(
                    color: _textHi,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'BRACKET',
                  style: AppTypography.textXxsBold.copyWith(
                    color: _textLo,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hasEvent ? title : 'Knockout Bracket',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXlBold.copyWith(
                color: _textHi,
                fontSize: 21,
                height: 1.15,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 3,
              decoration: BoxDecoration(
                color: _cyan,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _hairline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(_padH, 15, _padH, 16),
      child: Row(
        children: [
          _logoBadge(30),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ChessEver',
                style: AppTypography.textSmBold.copyWith(
                  color: _textHi,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Follow live chess',
                style: AppTypography.textXxsMedium.copyWith(
                  color: _textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'chessever.com',
            style: AppTypography.textXsBold.copyWith(
              color: _cyan,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBadge(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          PngAsset.newAppLogo,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
