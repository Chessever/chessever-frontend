import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

typedef PrepManualImporter =
    Future<bool> Function({
      required String alias,
      required String label,
      String? pgn,
    });

Future<void> showPrepImportDialog(
  BuildContext context, {
  required String playerName,
  required PrepManualImporter onImport,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        PrepImportDialog(playerName: playerName, onImport: onImport),
  ),
);

/// A keyboard-safe editor for either local databases or pasted games.
class PrepImportDialog extends StatefulWidget {
  const PrepImportDialog({
    super.key,
    required this.playerName,
    required this.onImport,
  });
  final String playerName;
  final PrepManualImporter onImport;

  @override
  State<PrepImportDialog> createState() => _PrepImportDialogState();
}

class _PrepImportDialogState extends State<PrepImportDialog> {
  late final _alias = TextEditingController(text: widget.playerName);
  final _label = TextEditingController(text: 'Manual PGN');
  final _pgn = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _alias.dispose();
    _label.dispose();
    _pgn.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool files}) async {
    if (_busy || _alias.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imported = await widget.onImport(
        alias: _alias.text.trim(),
        label: _label.text.trim().isEmpty ? 'Manual PGN' : _label.text.trim(),
        pgn: files ? null : _pgn.text.trim(),
      );
      if (mounted && imported) Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background,
    appBar: AppBar(title: const Text('Import PGN')),
    body: SafeArea(
      top: false,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Text(
            'Use the player’s name exactly as it appears in the PGN. Only their games are attached.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          const PrepFieldLabel('Player name in the PGN'),
          TextField(
            key: const ValueKey('prep_import_alias'),
            controller: _alias,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            decoration: prepInputDecoration(context, hint: 'Player name'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _busy || _alias.text.trim().isEmpty
                ? null
                : () => _submit(files: true),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Choose PGN files'),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: context.colors.textPrimary,
            ),
          ),
          Text(
            'PGN, PGN.bz2 and PGN.zst. Multiple files can be attached together.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          const PrepFieldLabel('Source label'),
          TextField(
            key: const ValueKey('prep_import_label'),
            controller: _label,
            enabled: !_busy,
            decoration: prepInputDecoration(context, hint: 'Manual PGN'),
          ),
          const SizedBox(height: 20),
          const PrepFieldLabel('Paste PGN'),
          TextField(
            key: const ValueKey('prep_import_pgn'),
            controller: _pgn,
            enabled: !_busy,
            minLines: 6,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: prepInputDecoration(
              context,
              hint: 'Paste one or more games',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: 24),
          PrepDialogActions(
            confirmLabel: 'Attach pasted games',
            busy: _busy,
            onConfirm:
                _busy || _alias.text.trim().isEmpty || _pgn.text.trim().isEmpty
                ? null
                : () => _submit(files: false),
          ),
        ],
      ),
    ),
  );
}
