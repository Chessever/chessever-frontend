import 'package:chessever2/screens/standings/utils/scorecard_name_actions.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Same ink as [showAppSnack] — the black capsule is the app's transient
/// teaching surface, not a Material yellow tooltip.
const Color _coachmarkInk = Color(0xFF08080A);

/// Tappable player/team identity that opens the existing share preview.
///
/// The name itself is the control. A one-time coachmark, drawn in the same
/// black capsule as snacks, teaches the tap. There is no permanent share icon,
/// outward arrow, or intermediate action menu.
class PlayerNameShareTarget extends StatefulWidget {
  const PlayerNameShareTarget({
    required this.playerName,
    required this.onShare,
    required this.child,
    this.coachmarkMessage,
    this.coachmarkEnabled = true,
    this.coachmarkTracker,
    super.key,
  });

  final String playerName;
  final Future<void> Function() onShare;
  final Widget child;
  final String? coachmarkMessage;
  final bool coachmarkEnabled;

  /// Override for tests. Production uses [playerNameShareCoachmarkTracker].
  final ScorecardNameCoachmarkTracker? coachmarkTracker;

  @override
  State<PlayerNameShareTarget> createState() => _PlayerNameShareTargetState();
}

class _PlayerNameShareTargetState extends State<PlayerNameShareTarget> {
  final GlobalKey<TooltipState> _coachmarkKey = GlobalKey<TooltipState>();
  bool _coachmarkCheckScheduled = false;

  ScorecardNameCoachmarkTracker get _tracker =>
      widget.coachmarkTracker ?? playerNameShareCoachmarkTracker;

  @override
  void initState() {
    super.initState();
    _scheduleCoachmark();
  }

  @override
  void didUpdateWidget(covariant PlayerNameShareTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.coachmarkEnabled && widget.coachmarkEnabled) {
      _scheduleCoachmark();
    }
  }

  @override
  void dispose() {
    Tooltip.dismissAllToolTips();
    super.dispose();
  }

  void _scheduleCoachmark() {
    final message = widget.coachmarkMessage?.trim();
    if (!widget.coachmarkEnabled ||
        message == null ||
        message.isEmpty ||
        _coachmarkCheckScheduled) {
      return;
    }
    _coachmarkCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await displayScorecardNameCoachmark(
          tracker: _tracker,
          isEligible: () => mounted && widget.coachmarkEnabled,
          showTooltip:
              () => _coachmarkKey.currentState?.ensureTooltipVisible() ?? false,
        );
      } finally {
        if (mounted) _coachmarkCheckScheduled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = Semantics(
      button: true,
      label: 'Share ${widget.playerName}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          Tooltip.dismissAllToolTips();
          await widget.onShare();
        },
        child: widget.child,
      ),
    );

    final message = widget.coachmarkMessage?.trim();
    if (message == null || message.isEmpty) return target;

    return Tooltip(
      key: _coachmarkKey,
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      preferBelow: true,
      showDuration: const Duration(seconds: 6),
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        color: _coachmarkInk,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      textStyle: AppTypography.textSmMedium.copyWith(
        color: Colors.white.withValues(alpha: 0.94),
      ),
      child: target,
    );
  }
}
