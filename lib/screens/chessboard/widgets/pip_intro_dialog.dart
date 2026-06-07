import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      final mq = MediaQuery.of(dialogContext);

      return Dialog(
        backgroundColor: colors.surface,
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22.br),
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
                              color: colors.textPrimary.withValues(alpha: 0.6),
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
              Divider(height: 1, color: colors.textPrimary.withValues(alpha: 0.08)),

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
                      SizedBox(height: 24.h),
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
                        mockup: const _PhoneFrame(child: _LiveActivityScreen()),
                      ),
                    ],
                  ),
                ),
              ),

              // ---- Footer actions ----
              Divider(height: 1, color: colors.textPrimary.withValues(alpha: 0.08)),
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

/// A phone bezel + notch wrapping a [child] "screen".
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124.w,
      height: 232.h,
      padding: EdgeInsets.all(5.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(26.br),
        border: Border.all(color: const Color(0xFF34343A), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21.br),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(top: 5.h),
                width: 40.w,
                height: 8.h,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6.br),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Another app" with the ChessEver board floating in the corner (PiP).
class _PipScreen extends StatelessWidget {
  const _PipScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0C0E),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(11.w, 22.h, 11.w, 11.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(54.w, 9.h, 0.10),
                SizedBox(height: 11.h),
                _bar(96.w, 6.h, 0.06),
                SizedBox(height: 6.h),
                _bar(86.w, 6.h, 0.06),
                SizedBox(height: 6.h),
                _bar(92.w, 6.h, 0.06),
              ],
            ),
          ),
          Positioned(
            right: 7.w,
            bottom: 10.h,
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

/// A lock screen with the Live Activity card on it.
class _LiveActivityScreen extends StatelessWidget {
  const _LiveActivityScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF11161F), Color(0xFF0B0D12)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(8.w, 26.h, 8.w, 10.h),
      child: Column(
        children: [
          Text(
            '9:41',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 30.f,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            'Monday, June 8',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9.f,
            ),
          ),
          SizedBox(height: 14.h),
          const _LiveActivityCard(),
        ],
      ),
    );
  }
}

/// The Live Activity card: eval bar + board + players + last move/eval.
class _LiveActivityCard extends StatelessWidget {
  const _LiveActivityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(6.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4.w,
            height: 46.w,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2.br)),
            child: Column(
              children: [
                Expanded(flex: 38, child: Container(color: const Color(0xFF2A2A2A))),
                Expanded(flex: 62, child: Container(color: Colors.white)),
              ],
            ),
          ),
          SizedBox(width: 5.w),
          const _MiniBoard(size: 46),
          SizedBox(width: 8.w),
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
                    Text(
                      'Nf3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.f,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
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
            border: dim
                ? null
                : Border.all(color: kPrimaryColor, width: 1),
          ),
        ),
        SizedBox(width: 5.w),
        Container(
          width: dim ? 42.w : 54.w,
          height: 6.h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: dim ? 0.22 : 0.85),
            borderRadius: BorderRadius.circular(3.br),
          ),
        ),
      ],
    );
  }
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
                      color: (p[3] as bool)
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

/// The floating PiP window: a thin eval bar + a mini board, shadowed.
class _FloatingBoardCard extends StatelessWidget {
  const _FloatingBoardCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(3.sp),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3.w,
            height: 44.w,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2.br)),
            child: Column(
              children: [
                Expanded(flex: 42, child: Container(color: const Color(0xFF2A2A2A))),
                Expanded(flex: 58, child: Container(color: Colors.white)),
              ],
            ),
          ),
          SizedBox(width: 3.w),
          const _MiniBoard(size: 44),
        ],
      ),
    );
  }
}
