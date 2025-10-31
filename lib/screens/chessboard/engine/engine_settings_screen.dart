import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EngineSettingsScreen extends ConsumerStatefulWidget {
  const EngineSettingsScreen({super.key});

  @override
  ConsumerState<EngineSettingsScreen> createState() => _EngineSettingsScreenState();
}

class _EngineSettingsScreenState extends ConsumerState<EngineSettingsScreen> {
  late bool _preferLocal;
  late double _multiPv;
  late double _threads;
  late double _hashMb;
  late double _timeoutMs;
  late double _maxDepth;
  bool _capDepth = false;

  @override
  void initState() {
    super.initState();
    final value = ref.read(engineSettingsProvider).valueOrNull ?? const EngineSettings();
    _preferLocal = value.preferLocal;
    _multiPv = value.multiPv.toDouble();
    _threads = value.threads.toDouble();
    _hashMb = value.hashMb.toDouble();
    _timeoutMs = value.timeoutMs.toDouble();
    _capDepth = value.maxDepth != null;
    _maxDepth = (value.maxDepth ?? 18).toDouble();
  }

  Future<void> _save() async {
    final notifier = ref.read(engineSettingsProvider.notifier);
    await notifier.update(
      EngineSettings(
        preferLocal: _preferLocal,
        multiPv: _multiPv.round().clamp(1, 5),
        threads: _threads.round().clamp(1, 8),
        hashMb: _hashMb.round().clamp(16, 1024),
        maxDepth: _capDepth ? _maxDepth.round().clamp(8, 40) : null,
        timeoutMs: _timeoutMs.round().clamp(1000, 20000),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(engineSettingsProvider);
    final loading = async.isLoading && async.valueOrNull == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine Settings'),
        actions: [
          TextButton(
            onPressed: loading ? null : _save,
            child: const Text('Save', style: TextStyle(color: kPrimaryColor)),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.sp),
              children: [
                SwitchListTile.adaptive(
                  value: _preferLocal,
                  onChanged: (v) => setState(() => _preferLocal = v),
                  title: const Text('Prefer Local Engine (dynamic)'),
                  subtitle: const Text('Use on-device Stockfish with progressive deepening'),
                  activeColor: kPrimaryColor,
                ),
                SizedBox(height: 8.h),
                _LabeledSlider(
                  title: 'MultiPV',
                  value: _multiPv,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  unit: ' lines',
                  onChanged: (v) => setState(() => _multiPv = v),
                ),
                _LabeledSlider(
                  title: 'Threads',
                  value: _threads,
                  min: 1,
                  max: 8,
                  divisions: 7,
                  unit: '',
                  onChanged: (v) => setState(() => _threads = v),
                ),
                _LabeledSlider(
                  title: 'Hash',
                  value: _hashMb,
                  min: 16,
                  max: 1024,
                  divisions: 63,
                  unit: ' MB',
                  onChanged: (v) => setState(() => _hashMb = v),
                ),
                SwitchListTile.adaptive(
                  value: _capDepth,
                  onChanged: (v) => setState(() => _capDepth = v),
                  title: const Text('Cap Max Depth'),
                  subtitle: const Text('Stop deepening beyond the selected max depth'),
                  activeColor: kPrimaryColor,
                ),
                if (_capDepth)
                  _LabeledSlider(
                    title: 'Max Depth',
                    value: _maxDepth,
                    min: 8,
                    max: 40,
                    divisions: 32,
                    unit: '',
                    onChanged: (v) => setState(() => _maxDepth = v),
                  ),
                _LabeledSlider(
                  title: 'Timeout',
                  value: _timeoutMs,
                  min: 1000,
                  max: 20000,
                  divisions: 19,
                  unit: ' ms',
                  onChanged: (v) => setState(() => _timeoutMs = v),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Supabase is the source of truth. Settings are cached locally for offline use and sync on login.',
                  style: TextStyle(color: kWhiteColor70, fontSize: 12.sp),
                ),
              ],
            ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: kWhiteColor)),
            Text('${value.round()}$unit', style: const TextStyle(color: kWhiteColor70)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: kPrimaryColor,
          label: value.round().toString(),
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

