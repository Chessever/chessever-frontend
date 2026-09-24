import 'dart:async';

import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_sheet_session_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sources.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceText;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Opens the add sheet for one My Space row, over My Space itself: search and
/// suggestions for what the row holds, each added (or taken back) with one
/// tap. Nothing navigates away. What was added waits behind the sheet and
/// springs into the row as it closes, with one Undo for all of it.
Future<void> showSpaceAddSheet(
  BuildContext context,
  WidgetRef ref,
  SpaceSection section,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(spaceSheetSessionProvider.notifier);
  session.state = SpaceSheetSession(section: section);
  final titles = <String, String>{};

  void openEditor(String fen) {
    HapticFeedbackService.navigation();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => boardEditorAt(fen)),
      ),
    );
  }

  try {
    await showSmoothBottomSheet<void>(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      builder: (sheetContext) => SpaceAddSheet(
        section: section,
        onAdded: (draft) => titles[draft.key] = draft.title,
        onOpenEditor: (fen) {
          Navigator.of(sheetContext).pop();
          openEditor(fen);
        },
      ),
    );
  } finally {
    final added = session.state?.added ?? const <String>{};
    session.state = null;
    if (added.isNotEmpty && messenger != null && messenger.mounted) {
      final store = container.read(spaceShortcutsProvider.notifier);
      final message = added.length == 1
          ? 'Added ${titles[added.first] ?? 'it'} to ${section.title}'
          : 'Added ${added.length} to ${section.title}';
      showAppSnackOn(
        messenger,
        message,
        tone: AppSnackTone.success,
        actionLabel: 'Undo',
        onAction: () async {
          final list =
              container.read(spaceShortcutsProvider).valueOrNull ?? const [];
          for (final s in list) {
            if (added.contains(s.key)) {
              await store.removeTarget(s.kind, s.targetId);
            }
          }
        },
      );
    }
  }
}

/// The sheet's content: a title with Done, a search field, and the row's
/// suggestion groups (or search results) underneath.
class SpaceAddSheet extends ConsumerStatefulWidget {
  const SpaceAddSheet({
    super.key,
    required this.section,
    this.onAdded,
    this.onOpenEditor,
  });

  final SpaceSection section;

  /// Told about every shortcut the sheet adds, for the closing snack.
  final ValueChanged<SpaceShortcut>? onAdded;

  /// Closes the sheet and opens the board editor on a position.
  final ValueChanged<String>? onOpenEditor;

  @override
  ConsumerState<SpaceAddSheet> createState() => _SpaceAddSheetState();
}

class _SpaceAddSheetState extends ConsumerState<SpaceAddSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  /// One line under the field for a request the sheet could not act on.
  String? _notice;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _notice = null;
      });
    });
  }

  Future<void> _toggle(SpaceShortcut draft) async {
    final store = ref.read(spaceShortcutsProvider.notifier);
    final session = ref.read(spaceSheetSessionProvider.notifier);
    if (_notice != null) setState(() => _notice = null);
    if (ref.read(spaceShortcutExistsProvider(draft.key))) {
      session.update((s) => s?.withoutAdded(draft.key));
      HapticFeedbackService.light();
      await store.removeTarget(draft.kind, draft.targetId);
      return;
    }
    // Held back from the row before it lands, so it never flashes in behind
    // the sheet.
    session.update((s) => s?.withAdded(draft.key));
    HapticFeedbackService.success();
    widget.onAdded?.call(draft);
    await store.add(draft);
  }

  void _say(String notice) {
    if (!mounted) return;
    setState(() => _notice = notice);
  }

  void _close() => Navigator.of(context).maybePop();

  void _openEditor(String fen) => widget.onOpenEditor?.call(fen);

  // The sheet rebuilds on every frame of the keyboard slide (its own inset,
  // and the host sheet reads the whole MediaQuery). Handing back the same
  // body instance lets Flutter skip the suggestion list and the Smart Event
  // builder until the query actually changes.
  Widget? _body;
  (SpaceSection, String, bool, Set<String>?)? _bodyKey;

  /// What My Space held when the sheet opened: the Openings suggestions list
  /// what is not in it first. Taken once, as soon as the list is known, so
  /// the order holds while the sheet is open.
  Set<String>? _pinnedAtOpen;

  Set<String>? _pinned() {
    if (_pinnedAtOpen case final pinned?) return pinned;
    if (widget.section != SpaceSection.openings) return null;
    // Watched only until the list is known; after that the snapshot stands
    // and adds or removes made here do not rebuild the sheet.
    final list = ref.watch(
      spaceShortcutsProvider.select((value) => value.valueOrNull),
    );
    if (list == null) return null;
    return _pinnedAtOpen = {for (final s in list) s.key};
  }

  Widget _content() {
    final editor = widget.onOpenEditor != null;
    final pinned = _pinned();
    final key = (widget.section, _query, editor, pinned);
    if (_body case final body? when _bodyKey == key) return body;
    _bodyKey = key;
    return _body = widget.section == SpaceSection.smartEvents
        ? SmartEventBuilder(onToggle: _toggle, onDone: _close)
        : SpaceAddSources(
            section: widget.section,
            query: _query,
            onToggle: _toggle,
            onOpenEditor: editor ? _openEditor : null,
            onNotice: _say,
            pinnedAtOpen: pinned ?? const <String>{},
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = SpaceMetricsSheet.gutter;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final hint = spaceSheetSearchHint(widget.section);

    // Smart Events are built, not picked from a list: every Events filter on
    // one screen, added with the same toggle, snack and Undo as any row.
    if (widget.section == SpaceSection.smartEvents) {
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: _content(),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 4.w),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Add to ${widget.section.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: spaceText(
                        context,
                        size: 18,
                        line: 24,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _DoneButton(onTap: _close),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 4.w, gutter, 0),
            child: _SearchField(
              controller: _controller,
              focusNode: _focus,
              hint: hint,
              onChanged: _onChanged,
              onClear: () {
                _controller.clear();
                _debounce?.cancel();
                setState(() => _query = '');
              },
            ),
          ),
          if (_notice case final notice?)
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 8.w, gutter, 0),
              // Announced: the notice is the only sign a tap was refused.
              child: Semantics(
                liveRegion: true,
                child: Text(
                  notice,
                  style: spaceText(
                    context,
                    size: 13,
                    line: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          Flexible(child: _content()),
        ],
      ),
    );
  }
}

/// Layout numbers shared by the sheet and its rows.
abstract final class SpaceMetricsSheet {
  static double get gutter => 16.w;

  /// The tallest a row's visual may be; also the width its column reserves.
  static double get lead => 40.w;

  /// Every row is at least this tall, so each is a full touch target.
  static const double rowMin = 56;

  /// The add toggle's touch target.
  static const double toggle = 44;
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    void tap() {
      HapticFeedbackService.buttonPress();
      onTap();
    }

    // excludeSemantics drops the detector's own tap action, so the button
    // carries it for TalkBack and Switch Access.
    return Semantics(
      button: true,
      label: 'Done',
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
          // Label flush right so it lines up with the search field below;
          // the target grows leftward.
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              'Done',
              style: spaceText(
                context,
                size: 15,
                line: 20,
                weight: FontWeight.w600,
                color: context.colors.accentText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = spaceText(context, size: 15, line: 20);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(10.w),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(Icons.search_rounded, size: 20.w, color: colors.textSecondary),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                cursorColor: colors.accentText,
                style: style,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: style.copyWith(color: colors.textSecondary),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.w),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return SizedBox(width: 12.w);
                return Semantics(
                  button: true,
                  label: 'Clear search',
                  excludeSemantics: true,
                  onTap: onClear,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClear,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.close_rounded,
                        size: 18.w,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The add control: a drawn "+" that turns into a check once the thing is in
/// My Space, on a spring, and back. Presses to 0.97. Bare mark, no fill.
class SpaceAddToggle extends StatefulWidget {
  const SpaceAddToggle({
    super.key,
    required this.added,
    required this.onTap,
    required this.label,
  });

  final bool added;
  final VoidCallback onTap;

  /// What the control does, for a screen reader ("Add Carlsen").
  final String label;

  @override
  State<SpaceAddToggle> createState() => _SpaceAddToggleState();
}

class _SpaceAddToggleState extends State<SpaceAddToggle> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Motion morph = still
        ? const Motion.none()
        : const CupertinoMotion.snappy();
    return Semantics(
      // No `toggled`: the label already names the action ("Add X" /
      // "Remove X from My Space"), and an "on" state beside "Remove" reads
      // as a contradiction.
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: SizedBox.square(
          dimension: SpaceMetricsSheet.toggle,
          child: SingleMotionBuilder(
            motion: still
                ? const Motion.none()
                : const CupertinoMotion.bouncy(),
            value: _pressed ? 0.97 : 1.0,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: SingleMotionBuilder(
              motion: morph,
              value: widget.added ? 1.0 : 0.0,
              builder: (context, t, _) => CustomPaint(
                painter: _PlusCheckPainter(
                  t: t,
                  plus: colors.textPrimary,
                  check: colors.accentText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two rounded strokes on a 20-unit grid, centred in the paint box: the "+"
/// (a vertical and a horizontal bar) at t = 0, the check (short and long
/// stroke) at t = 1. Each bar travels to its stroke, so the mark reshapes
/// rather than swapping.
class _PlusCheckPainter extends CustomPainter {
  const _PlusCheckPainter({
    required this.t,
    required this.plus,
    required this.check,
  });

  final double t;
  final Color plus;
  final Color check;

  @override
  void paint(Canvas canvas, Size size) {
    const unit = 20.0;
    final k = 18 / unit;
    final origin = Offset(
      (size.width - unit * k) / 2,
      (size.height - unit * k) / 2,
    );
    final p = t.clamp(0.0, 1.0);
    Offset at(Offset a, Offset b) => origin + Offset.lerp(a, b, p)! * k;
    final paint = Paint()
      ..color = Color.lerp(plus, check, p)!
      ..strokeWidth = 2.4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Vertical bar -> the check's short stroke.
    canvas.drawLine(
      at(const Offset(10, 3), const Offset(4, 10.5)),
      at(const Offset(10, 17), const Offset(8.2, 14.6)),
      paint,
    );
    // Horizontal bar -> the check's long stroke.
    canvas.drawLine(
      at(const Offset(3, 10), const Offset(8.2, 14.6)),
      at(const Offset(17, 10), const Offset(16.2, 5.6)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlusCheckPainter old) =>
      old.t != t || old.plus != plus || old.check != check;
}
