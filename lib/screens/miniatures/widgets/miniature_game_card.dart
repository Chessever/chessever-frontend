import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MiniatureGameCard extends StatelessWidget {
  const MiniatureGameCard({
    required this.miniature,
    required this.onTap,
    super.key,
    this.isOpening = false,
  });

  final GamebaseMiniature miniature;
  final VoidCallback onTap;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    final event = _clean(miniature.event) ?? 'Gamebase miniature';
    final whiteName = _clean(miniature.whiteName) ?? 'White';
    final blackName = _clean(miniature.blackName) ?? 'Black';
    final result = _resultLabel(miniature.result);
    final opening = _openingLabel(miniature);
    final semantics = <String>[
      'Miniature game',
      '$whiteName versus $blackName',
      result,
      'ended in ${miniature.finalMoveNumber} moves',
      event,
      if (opening != null) opening,
      isOpening ? 'loading complete game' : 'open complete game',
    ].join(', ');

    return Semantics(
      button: true,
      enabled: !isOpening,
      label: semantics,
      onTap: isOpening ? null : onTap,
      child: ExcludeSemantics(
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.colors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isOpening ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 188),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            event,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsMedium.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ),
                        if (miniature.date case final date?) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _compactDate(date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: AppTypography.textXsMedium.copyWith(
                                color: context.colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PlayerLine(
                      color: Colors.white,
                      outlineColor: context.colors.dividerStrong,
                      name: whiteName,
                      rating: miniature.whiteElo,
                      winner: miniature.result == MiniatureGameResult.whiteWins,
                    ),
                    const SizedBox(height: 8),
                    _PlayerLine(
                      color: const Color(0xFF232326),
                      outlineColor:
                          context.isLightTheme
                              ? const Color(0xFF232326)
                              : context.colors.dividerStrong,
                      name: blackName,
                      rating: miniature.blackElo,
                      winner: miniature.result == MiniatureGameResult.blackWins,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      opening ?? 'Opening information unavailable',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color:
                            opening == null
                                ? context.colors.textSecondary
                                : context.colors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _MetadataPill(
                                icon: CupertinoIcons.flag_fill,
                                label: '${miniature.finalMoveNumber} moves',
                              ),
                              _MetadataPill(
                                icon: _timeControlIcon(miniature.timeControl),
                                label: _timeControlLabel(miniature.timeControl),
                              ),
                              if (miniature.avgRating case final rating?)
                                _MetadataPill(
                                  icon: CupertinoIcons.chart_bar_fill,
                                  label: '$rating avg',
                                ),
                              _MetadataPill(
                                icon:
                                    miniature.isOnline
                                        ? CupertinoIcons.globe
                                        : CupertinoIcons.person_2_fill,
                                label: miniature.isOnline ? 'Online' : 'OTB',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child:
                                isOpening
                                    ? SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: context.colors.brand,
                                      ),
                                    )
                                    : Icon(
                                      CupertinoIcons.chevron_forward,
                                      size: 18,
                                      color: context.colors.iconSecondary,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({
    required this.color,
    required this.outlineColor,
    required this.name,
    required this.rating,
    required this.winner,
  });

  final Color color;
  final Color outlineColor;
  final String name;
  final int? rating;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: outlineColor),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        if (rating != null && rating! > 0) ...[
          const SizedBox(width: 8),
          Text(
            '$rating',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(width: 10),
        Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 28),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:
                winner
                    ? context.colors.success.withValues(alpha: 0.16)
                    : context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            winner ? '1' : '0',
            style: AppTypography.textSmBold.copyWith(
              color:
                  winner
                      ? (context.isLightTheme
                          ? context.colors.successStrong
                          : context.colors.success)
                      : context.colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.colors.iconSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXxsMedium.copyWith(
                color: context.colors.textSecondary,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _openingLabel(GamebaseMiniature miniature) {
  final eco = _clean(miniature.eco);
  final opening = _clean(miniature.opening);
  final variation = _clean(miniature.variation);
  final name = [
    if (opening != null) opening,
    if (variation != null && variation != opening) variation,
  ].join(' · ');
  if (eco == null && name.isEmpty) return null;
  if (eco == null) return name;
  if (name.isEmpty) return eco;
  return '$eco · $name';
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _resultLabel(MiniatureGameResult result) => switch (result) {
  MiniatureGameResult.whiteWins => 'White won 1-0',
  MiniatureGameResult.blackWins => 'Black won 0-1',
};

String _timeControlLabel(MiniatureGameTimeControl control) => switch (control) {
  MiniatureGameTimeControl.classical => 'Classical',
  MiniatureGameTimeControl.rapid => 'Rapid',
  MiniatureGameTimeControl.blitz => 'Blitz',
};

IconData _timeControlIcon(MiniatureGameTimeControl control) =>
    switch (control) {
      MiniatureGameTimeControl.classical => CupertinoIcons.clock_fill,
      MiniatureGameTimeControl.rapid => CupertinoIcons.timer_fill,
      MiniatureGameTimeControl.blitz => CupertinoIcons.bolt_fill,
    };

String _compactDate(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
