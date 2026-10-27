import 'package:chessever2/screens/my_prep/services/prep_pgn_player.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// One PGN to import: a chosen file, or the pasted text.
typedef PrepPgnInput = ({String label, String pgn});

/// The reader's chosen files, read; null when they chose none.
typedef PrepPgnPicker = Future<List<PrepPgnInput>?> Function();

/// Imports [inputs] as [player]'s games, or as whoever they belong to when
/// [player] is null. A reading that is not resolved holds the names to
/// choose between, and nothing was imported.
typedef PrepPgnImporter =
    Future<PrepPgnReading> Function(
      List<PrepPgnInput> inputs, {
      String? player,
    });

Future<void> showPrepImportDialog(
  BuildContext context, {
  required PrepPgnPicker pickFiles,
  required PrepPgnImporter onImport,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => PrepImportDialog(pickFiles: pickFiles, onImport: onImport),
  ),
);

/// Paste games or choose files; whose games they are is read from the PGN.
class PrepImportDialog extends StatefulWidget {
  const PrepImportDialog({
    super.key,
    required this.pickFiles,
    required this.onImport,
  });
  final PrepPgnPicker pickFiles;
  final PrepPgnImporter onImport;

  @override
  State<PrepImportDialog> createState() => _PrepImportDialogState();
}

class _PrepImportDialogState extends State<PrepImportDialog> {
  final _pgn = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The games waiting on the reader to say whose they are.
  List<PrepPgnInput>? _pending;
  List<PrepPgnCandidate> _candidates = const [];

  bool get _pasted => _pgn.text.trim().isNotEmpty;

  @override
  void dispose() {
    _pgn.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<List<PrepPgnInput>?> Function() read, {
    String? player,
  }) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inputs = await read();
      if (inputs == null || !mounted) return;
      final reading = await widget.onImport(inputs, player: player);
      if (!mounted) return;
      if (reading.resolved) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _pending = inputs;
          _candidates = reading.candidates;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PrepException
              ? error.message
              : 'Could not import these games. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _import() => _pasted
      ? _run(() async => [(label: 'Pasted PGN', pgn: _pgn.text.trim())])
      : _run(widget.pickFiles);

  void _choose(PrepPgnCandidate candidate) {
    final inputs = _pending;
    if (inputs == null) return;
    _run(() async => inputs, player: candidate.name);
  }

  void _back() => setState(() {
    _pending = null;
    _candidates = const [];
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final choosing = _pending != null;
    return PopScope(
      canPop: !choosing,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && choosing) _back();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Import PGN')),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (choosing) ...[
                  Text(
                    'Whose games are these?',
                    style: AppTypography.textMdBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _candidates.length,
                      separatorBuilder: (_, _) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) => _CandidateRow(
                        candidate: _candidates[index],
                        onTap: _busy ? null : () => _choose(_candidates[index]),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Semantics(
                      label: 'PGN',
                      textField: true,
                      child: TextField(
                        key: const ValueKey('prep_import_pgn'),
                        controller: _pgn,
                        enabled: !_busy,
                        expands: true,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => setState(() {}),
                        style: AppTypography.textSmRegular.copyWith(
                          color: colors.textPrimary,
                        ),
                        decoration: prepInputDecoration(
                          context,
                          hint: 'Paste PGN',
                        ),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(
                      _error!,
                      style: AppTypography.textSmRegular.copyWith(
                        color: colors.danger,
                      ),
                    ),
                  ),
                SizedBox(height: 16.h),
                if (!choosing)
                  PrepDialogActions(
                    confirmLabel: _pasted ? 'Import' : 'Choose files',
                    busy: _busy,
                    onConfirm: _busy ? null : _import,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A name the games could belong to, as a source row reads.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.onTap});

  final PrepPgnCandidate candidate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12.br),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('prep_import_player_${candidate.name}'),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  candidate.name,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                prepGamesLabel(candidate.games),
                style: AppTypography.textXsRegular.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
