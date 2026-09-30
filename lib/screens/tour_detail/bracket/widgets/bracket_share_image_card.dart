import 'dart:typed_data';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:flutter/material.dart';

/// Branded frame around a live snapshot of the knockout bracket canvas.
///
/// The [snapshot] is the raw viewport capture the user framed by panning/zooming
/// the bracket (see `captureBoundaryPng` + `bracketShareBoundaryKeyProvider`).
/// This card wraps it in the same ChessEver header/footer chrome as the other
/// share images so the shared artifact is on-brand and X/Twitter-sized. Rendered
/// off-screen via `captureCardPng`, in the capture's [ShareCardPalette].
///
/// The snapshot is transparent where empty. Dark lets it take on the card's
/// page. Paper sets it on the live canvas's own mint ground, because the
/// bracket's paper match cards are the same tone as the paper card page and
/// would otherwise lose their lift.
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

  static const _padH = 22.0;

  /// What shows through the snapshot's empty (transparent) canvas: the
  /// light theme's page, the ground the live bracket is drawn on, in paper;
  /// nothing in dark, which keeps its historical look.
  @visibleForTesting
  static Color? snapshotGround(ShareCardPalette p) =>
      p.isLight ? AppColors.light.background : null;

  @override
  Widget build(BuildContext context) {
    final ratio =
        snapshotAspectRatio.isFinite && snapshotAspectRatio > 0
            ? snapshotAspectRatio
            : 3 / 4;
    final p = ShareCardPalette.of(context);

    return MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: p.bg,
          child: SizedBox(
            width: width,
            child: ShareCardColumn(
              children: [
                _buildHeader(p),
                Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 4, _padH, 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: snapshotGround(p),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.tileEdge ?? p.hairline),
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
                _buildFooter(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ShareCardPalette p) {
    final title = eventName?.trim();
    final hasEvent = title != null && title.isNotEmpty;

    return DecoratedBox(
      // Paper keeps a flat header; dark washes it with cyan.
      decoration:
          p.heroTint > 0
              ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      p.accentFill.withValues(alpha: p.heroTint),
                      p.bg,
                    ),
                    p.bg,
                  ],
                ),
              )
              : const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _logoBadge(26, p),
                const SizedBox(width: 9),
                Text(
                  'ChessEver',
                  style: AppTypography.textSmBold.copyWith(
                    color: p.textHi,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'BRACKET',
                  style: AppTypography.textXxsBold.copyWith(
                    color: p.textLo,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hasEvent ? title : 'Knockout Bracket',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXlBold.copyWith(
                color: p.textHi,
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
                color: p.accentFill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(ShareCardPalette p) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(_padH, 15, _padH, 16),
      child: Row(
        children: [
          _logoBadge(30, p),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ChessEver',
                style: AppTypography.textSmBold.copyWith(
                  color: p.textHi,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                kShareFooterSlogan,
                style: AppTypography.textXxsMedium.copyWith(
                  color: p.textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'chessever.com',
            style: AppTypography.textXsBold.copyWith(
              color: p.accentInk,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBadge(double size, ShareCardPalette p) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow:
            p.logoGlow
                ? [
                  BoxShadow(
                    color: p.accentFill.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ]
                : null,
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
