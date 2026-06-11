import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// One-time flag: the live-game-widgets intro (PiP + Live Activity) was shown.
const String kLiveWidgetsIntroSeenKey = 'live_widgets_intro_seen';

/// A large, one-time intro that teaches BOTH live-game widgets — Picture-in-
/// Picture and the Live Activity / lock-screen card — each with a phone mockup
/// and how to turn it on. [onOpenSettings] runs after the dialog closes when the
/// user taps "Open Settings"; the caller routes to the notification settings.
Future<void> showLiveWidgetsIntroDialog(
  BuildContext context, {
  required VoidCallback onOpenSettings,
}) {
  return showAlertModal<void>(
    context: context,
    horizontalPadding: 16,
    verticalPadding: 24,
    child: Builder(
      builder: (dialogContext) {
        final colors = dialogContext.colors;
        final mq = MediaQuery.of(dialogContext);

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22.br),
            border: Border.all(
              color: colors.textPrimary.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460.w,
              maxHeight: mq.size.height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- Header ----
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 20.h, 12.w, 12.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Follow games without the app open',
                              style: AppTypography.textLgBold.copyWith(
                                color: colors.textPrimary,
                                fontSize: 18.f,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'Two ways to keep watching a live game while you '
                              'do other things.',
                              style: AppTypography.textSmRegular.copyWith(
                                color: colors.textPrimary.withValues(
                                  alpha: 0.6,
                                ),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.textPrimary.withValues(alpha: 0.5),
                          size: 22.ic,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colors.textPrimary.withValues(alpha: 0.08),
                ),

                // ---- Scrollable body: the two features ----
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 18.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FeatureBlock(
                          icon: Icons.picture_in_picture_alt_rounded,
                          title: 'Picture-in-Picture',
                          description:
                              'A floating mini-board that stays on top of other '
                              'apps and follows the game live.',
                          steps: const [
                            'Turn it on in Settings → Notifications → '
                                'Picture in Picture.',
                            'Open a live game, then leave the app — the board '
                                'keeps playing in a floating window.',
                          ],
                          mockup: const _PhoneFrame(child: _PipScreen()),
                        ),
                        SizedBox(height: 26.h),
                        _FeatureBlock(
                          icon: Icons.lock_clock_outlined,
                          title: 'Live Activity',
                          description:
                              'A lock-screen card with the board, players and '
                              'evaluation, updated on every move.',
                          steps: const [
                            'Turn it on in Settings → Notifications → '
                                'Live Activity.',
                            'Open a live game and lock your phone — the card '
                                'sits right on your lock screen.',
                          ],
                          mockup: const _PhoneFrame(
                            child: _LiveActivityScreen(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- Footer actions ----
                Divider(
                  height: 1,
                  color: colors.textPrimary.withValues(alpha: 0.08),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 14.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            'Got it',
                            style: AppTypography.textSmMedium.copyWith(
                              color: colors.textPrimary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            onOpenSettings();
                          },
                          child: Text(
                            'Open Settings',
                            style: AppTypography.textSmBold.copyWith(
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One feature: a phone mockup beside an icon + title + description + steps.
class _FeatureBlock extends StatelessWidget {
  const _FeatureBlock({
    required this.icon,
    required this.title,
    required this.description,
    required this.steps,
    required this.mockup,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> steps;
  final Widget mockup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mockup,
        SizedBox(width: 16.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.sp),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                    child: Icon(icon, color: kPrimaryColor, size: 16.ic),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.textMdBold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                description,
                style: AppTypography.textSmRegular.copyWith(
                  color: colors.textPrimary.withValues(alpha: 0.7),
                  height: 1.35,
                ),
              ),
              SizedBox(height: 12.h),
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) SizedBox(height: 8.h),
                _Step(number: '${i + 1}', text: steps[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18.w,
          height: 18.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kPrimaryColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AppTypography.textXsBold.copyWith(color: kPrimaryColor),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: AppTypography.textXsMedium.copyWith(
              color: colors.textPrimary.withValues(alpha: 0.82),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mockups (pure widgets, no assets)
// ---------------------------------------------------------------------------

/// A phone bezel with a Dynamic-Island notch, home indicator and subtle screen
/// depth, wrapping a [child] "screen".
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138.w,
      height: 262.h,
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(30.br),
        border: Border.all(color: const Color(0xFF3B3B43), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26.br),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            // Screen depth: faint top highlight + bottom shade.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.05),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.20),
                      ],
                      stops: const [0.0, 0.22, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Dynamic-Island notch.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(top: 6.h),
                width: 42.w,
                height: 12.h,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(7.br),
                ),
              ),
            ),
            // Home indicator.
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(bottom: 6.h),
                width: 46.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2.br),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Another app" (a media/article screen) with the ChessEver board floating in
/// the corner — i.e. what Picture-in-Picture looks like.
class _PipScreen extends StatelessWidget {
  const _PipScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0F12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 24.h),
              // App bar: back chevron + title.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 11.w),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 9.ic,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    SizedBox(width: 7.w),
                    Container(
                      width: 56.w,
                      height: 7.h,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(3.br),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 11.h),
              // Hero media block with a play button.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 11.w),
                child: Container(
                  height: 62.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C2532), Color(0xFF12161D)],
                    ),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Center(
                    child: Container(
                      width: 26.w,
                      height: 26.w,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 16.ic,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 11.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 11.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(98.w, 6.h, 0.12),
                    SizedBox(height: 6.h),
                    _bar(84.w, 5.h, 0.07),
                    SizedBox(height: 5.h),
                    _bar(92.w, 5.h, 0.07),
                  ],
                ),
              ),
            ],
          ),
          // The floating PiP window.
          Positioned(
            right: 8.w,
            bottom: 14.h,
            child: const _FloatingBoardCard(),
          ),
        ],
      ),
    );
  }

  Widget _bar(double w, double h, double alpha) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(3.br),
    ),
  );
}

/// The floating PiP window: a drag grabber, a thin eval bar + a mini board,
/// shadowed with a soft accent glow.
class _FloatingBoardCard extends StatelessWidget {
  const _FloatingBoardCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4.sp, 3.sp, 4.sp, 4.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(9.br),
        border: Border.all(
          color: kPrimaryColor.withValues(alpha: 0.25),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.12),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14.w,
            height: 2.5.h,
            margin: EdgeInsets.only(bottom: 3.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _EvalBar(boardSize: 44, whiteFlex: 58),
              _GapW(3),
              _MiniBoard(size: 44),
            ],
          ),
        ],
      ),
    );
  }
}

/// A lock screen (wallpaper + clock) with the Live Activity card on it.
class _LiveActivityScreen extends StatelessWidget {
  const _LiveActivityScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16213C), Color(0xFF0C1018), Color(0xFF080A0E)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(8.w, 24.h, 8.w, 12.h),
      child: Column(
        children: [
          Icon(
            Icons.lock_rounded,
            size: 11.ic,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          SizedBox(height: 8.h),
          Text(
            '9:41',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 34.f,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            'Monday, June 8',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9.f,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16.h),
          const _LiveActivityCard(),
        ],
      ),
    );
  }
}

/// The Live Activity card: an app row, then the eval bar + board + players.
class _LiveActivityCard extends StatelessWidget {
  const _LiveActivityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(7.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(13.br),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App row: logo + name + "now".
          Row(
            children: [
              Container(
                width: 13.w,
                height: 13.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(3.br),
                ),
                child: Text(
                  '♞',
                  style: TextStyle(
                    fontSize: 9.f,
                    height: 1,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(width: 5.w),
              Container(
                width: 48.w,
                height: 5.h,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3.br),
                ),
              ),
              const Spacer(),
              Text(
                'now',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 7.f,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _EvalBar(boardSize: 42, whiteFlex: 62),
              const _GapW(5),
              const _MiniBoard(size: 42),
              const _GapW(8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _nameRow(dim: false),
                    SizedBox(height: 5.h),
                    _nameRow(dim: true),
                    SizedBox(height: 7.h),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Nf3',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.f,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F1F22),
                            borderRadius: BorderRadius.circular(8.br),
                            border: Border.all(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '+1.2',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.f,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nameRow({required bool dim}) {
    return Row(
      children: [
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(
            color: dim ? const Color(0xFF3A3A3D) : Colors.white,
            shape: BoxShape.circle,
            border: dim ? null : Border.all(color: kPrimaryColor, width: 1),
          ),
        ),
        SizedBox(width: 5.w),
        Flexible(
          child: Container(
            height: 6.h,
            constraints: BoxConstraints(maxWidth: dim ? 40.w : 52.w),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: dim ? 0.22 : 0.85),
              borderRadius: BorderRadius.circular(3.br),
            ),
          ),
        ),
      ],
    );
  }
}

/// A vertical eval bar matching a board of [boardSize]; white fills [whiteFlex]%.
class _EvalBar extends StatelessWidget {
  const _EvalBar({required this.boardSize, this.whiteFlex = 58});

  final double boardSize;
  final int whiteFlex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3.5.w,
      height: boardSize.w,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(2.br)),
      child: Column(
        children: [
          Expanded(
            flex: 100 - whiteFlex,
            child: Container(color: const Color(0xFF2A2A2A)),
          ),
          Expanded(flex: whiteFlex, child: Container(color: Colors.white)),
        ],
      ),
    );
  }
}

/// A const horizontal gap (so the mockup rows can stay `const`).
class _GapW extends StatelessWidget {
  const _GapW(this.width);

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(width: width.w);
}

/// A tiny checkerboard with a few pieces, just enough to read as chess.
class _MiniBoard extends StatelessWidget {
  const _MiniBoard({required this.size});

  final double size;

  static const _light = Color(0xFFEAD7B4);
  static const _dark = Color(0xFFB17B4F);

  // row, col, glyph, isWhite — placed on cell centres of a 6×6 grid.
  static const _pieces = <List<Object>>[
    [0, 1, '♜', false],
    [0, 4, '♚', false],
    [1, 3, '♟', false],
    [4, 2, '♟', true],
    [5, 1, '♚', true],
    [5, 4, '♜', true],
  ];

  @override
  Widget build(BuildContext context) {
    const n = 6;
    final px = size.w;
    final cell = px / n;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4.br),
      child: SizedBox(
        width: px,
        height: px,
        child: Stack(
          children: [
            Column(
              children: List.generate(
                n,
                (r) => Expanded(
                  child: Row(
                    children: List.generate(
                      n,
                      (c) => Expanded(
                        child: Container(
                          color: (r + c).isEven ? _light : _dark,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (final p in _pieces)
              Positioned(
                left: (p[1] as int) * cell,
                top: (p[0] as int) * cell,
                width: cell,
                height: cell,
                child: Center(
                  child: Text(
                    p[2] as String,
                    style: TextStyle(
                      fontSize: cell * 0.84,
                      height: 1,
                      color:
                          (p[3] as bool)
                              ? const Color(0xFFF6F6F6)
                              : const Color(0xFF1E1E1E),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
