import 'dart:async';

import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// A real dialog owns focus, outside dismissal and the entire message stack.
/// It is mounted above the destination rather than owned by the tapped tile.
Future<void> showDiscoveryNudgeTooltip(
  BuildContext context, {
  required List<DiscoveryNudgeMessage> messages,
  Rect? target,
}) async {
  if (messages.isEmpty || !context.mounted) return;
  final open = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(editorialLinkOpenerProvider);
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  final overlayTarget = target == null || overlayBox == null
      ? null
      : overlayBox.globalToLocal(target.topLeft) & target.size;
  final originalSize = MediaQuery.sizeOf(context);
  // No scrim and no route fade: the tooltip is there, frosted, from its
  // first frame, and only its size settles.
  await showGlassDialog<void>(
    context: context,
    useSafeArea: false,
    scrim: Colors.transparent,
    scaleIn: false,
    builder: (dialogContext) => SafeArea(
      child: CustomSingleChildLayout(
        delegate: _TooltipLayout(
          MediaQuery.sizeOf(dialogContext) == originalSize
              ? overlayTarget?.shift(
                  -MediaQuery.paddingOf(dialogContext).topLeft,
                )
              : null,
        ),
        child: DiscoveryNudgeTooltip(
          messages: messages,
          onDismiss: () => Navigator.of(dialogContext).pop(),
          onSee: (uri) {
            Navigator.of(dialogContext).pop();
            unawaited(open(context, uri));
          },
        ),
      ),
    ),
  );
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.target);
  final Rect? target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 24).clamp(0, 320),
        maxHeight: (constraints.maxHeight - 24).clamp(0, 480),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = target;
    if (anchor == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: anchor.center,
      preferBelow: anchor.center.dy < size.height / 2,
      verticalOffset: anchor.height / 2 + 8,
      margin: 12,
    );
  }

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      oldDelegate.target != target;
}

/// Paged messages retain one footprint for the controls. Long text can scroll
/// at large accessibility sizes while See and the 44dp navigation stay visible.
class DiscoveryNudgeTooltip extends StatefulWidget {
  const DiscoveryNudgeTooltip({
    super.key,
    required this.messages,
    required this.onDismiss,
    required this.onSee,
  });
  final List<DiscoveryNudgeMessage> messages;
  final VoidCallback onDismiss;
  final ValueChanged<Uri> onSee;

  @override
  State<DiscoveryNudgeTooltip> createState() => _DiscoveryNudgeTooltipState();
}

class _DiscoveryNudgeTooltipState extends State<DiscoveryNudgeTooltip> {
  static const _settle = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
  );

  int _index = 0;

  // Fully readable from the first frame; only its size settles, as the
  // discovery bubble's does.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.messages[_index];
    final ink = context.colors.textPrimary;
    final panel = PopupGlass(
      tone: context.colors.popup,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label:
                          'Message ${_index + 1} of ${widget.messages.length}',
                      liveRegion: true,
                      excludeSemantics: true,
                      child: Text(
                        '${_index + 1}/${widget.messages.length}',
                        style: AppTypography.textSmMedium.copyWith(
                          color: ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close message',
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message.body,
                      key: ValueKey(_index),
                      style: AppTypography.textSmMedium.copyWith(color: ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (message.actionUrl case final uri?)
                    TextButton.icon(
                      onPressed: () => widget.onSee(uri),
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.north_east_rounded, size: 16),
                      label: const Text('See'),
                    ),
                  const Spacer(),
                  if (widget.messages.length > 1) ...[
                    IconButton(
                      tooltip: 'Previous message',
                      onPressed: _index == 0
                          ? null
                          : () => setState(() => _index--),
                      icon: const Icon(Icons.chevron_left),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next message',
                      onPressed: _index == widget.messages.length - 1
                          ? null
                          : () => setState(() => _index++),
                      icon: const Icon(Icons.chevron_right),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return SingleMotionBuilder(
      motion: _settle,
      value: _settled ? 1.0 : 0.94,
      active: !MediaQuery.disableAnimationsOf(context),
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: panel,
    );
  }
}
