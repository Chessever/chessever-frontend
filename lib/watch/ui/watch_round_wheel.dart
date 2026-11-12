import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../core/watch_models.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

/// Every round of a section on a wheel. The Digital Crown drives a wheel
/// natively and settles on whole rounds, so choosing round 9 of 11 is one
/// turn and one tap. The wheel opens on the round already shown; tapping
/// any round opens it.
class WatchRoundWheelPage extends StatefulWidget {
  const WatchRoundWheelPage({
    super.key,
    required this.rounds,
    required this.selectedId,
    this.now,
  });
  final List<WatchRound> rounds;
  final String? selectedId;

  /// Test seam for the round dates.
  final DateTime? now;

  @override
  State<WatchRoundWheelPage> createState() => _WatchRoundWheelPageState();
}

class _WatchRoundWheelPageState extends State<WatchRoundWheelPage> {
  late final FixedExtentScrollController _wheel;
  late int _centered;

  @override
  void initState() {
    super.initState();
    final index = widget.rounds.indexWhere((r) => r.id == widget.selectedId);
    _centered = index < 0 ? widget.rounds.length - 1 : index;
    _wheel = FixedExtentScrollController(initialItem: _centered);
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _choose(WatchRound round) {
    WatchHaptics.click();
    Navigator.of(context).pop(round);
  }

  String? _detail(WatchRound round, DateTime now, bool use24h) {
    if (round.id == widget.selectedId) return 'Showing now';
    final start = round.startsAt?.toLocal();
    if (start == null) return null;
    return watchWhen(start, now, use24h: use24h);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final scale = MediaQuery.textScalerOf(context);
    final now = widget.now ?? DateTime.now();
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final extent = scale.scale(50) + 6;
    return CupertinoPageScaffold(
      backgroundColor: WatchStyle.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          insets.left + 5,
          WatchStatusBar.heightOf(context) + 4,
          insets.right + 5,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: WatchPressable(
                onPressed: () {
                  WatchHaptics.click();
                  Navigator.of(context).maybePop();
                },
                builder: (context, _) => const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.chevron_back,
                      size: 18,
                      color: WatchStyle.ink,
                    ),
                    SizedBox(width: 4),
                    Text('Rounds', style: WatchStyle.body),
                  ],
                ),
              ),
            ),
            Expanded(
              child: WatchCrownScroll(
                child: ListWheelScrollView.useDelegate(
                  controller: _wheel,
                  itemExtent: extent,
                  diameterRatio: 2.4,
                  perspective: 0.004,
                  squeeze: 1,
                  overAndUnderCenterOpacity: 0.55,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (i) => setState(() => _centered = i),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: widget.rounds.length,
                    builder: (context, i) {
                      final round = widget.rounds[i];
                      final shown = round.id == widget.selectedId;
                      final detail = _detail(round, now, use24h);
                      return Semantics(
                        button: true,
                        selected: shown,
                        label: [round.name, ?detail].join('. '),
                        excludeSemantics: true,
                        onTap: () => _choose(round),
                        child: WatchPressable(
                          onPressed: () => _choose(round),
                          builder: (context, pressed) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: WatchStyle.contentInset,
                              ),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: pressed || i == _centered
                                    ? WatchStyle.surfacePressed
                                    : WatchStyle.surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          round.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: WatchStyle.body.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        if (detail != null)
                                          Text(
                                            detail,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: WatchStyle.figures,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (shown) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      CupertinoIcons.checkmark_alt,
                                      size: 16,
                                      color: WatchStyle.ink,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
