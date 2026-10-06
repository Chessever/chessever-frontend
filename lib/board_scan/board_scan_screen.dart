import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'board_scan_api.dart';
import 'board_scan_crop.dart';
import 'board_scan_image.dart';
import 'board_scan_position.dart';
import 'board_scan_preview.dart';

Future<String?> importBoardImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Import board image',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Choose a photo or diagram, then align the board.'),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  try {
    final picker = ImagePicker();
    // Android can destroy the activity while a native picker is open. Recover
    // its pending photo when the user next opens this flow.
    final recovered = defaultTargetPlatform == TargetPlatform.android
        ? await picker.retrieveLostData()
        : null;
    final file =
        recovered?.files?.firstOrNull ??
        await picker.pickImage(
          source: source,
          imageQuality: 95,
          maxWidth: 2048,
          maxHeight: 2048,
        );
    if (file == null || !context.mounted) return null;
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 20 MB.');
    }
    final image = await prepareBoardScanImage(await file.readAsBytes());
    if (!context.mounted) return null;
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            BoardScanScreen(image: image, photo: source == ImageSource.camera),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      showAppSnack(
        context,
        error is FormatException
            ? error.message
            : 'The image could not be opened. Check camera or photo access and try again.',
        tone: AppSnackTone.danger,
      );
    }
    return null;
  }
}

class BoardScanScreen extends StatefulWidget {
  const BoardScanScreen({super.key, required this.image, required this.photo});
  final BoardScanImage image;
  final bool photo;
  @override
  State<BoardScanScreen> createState() => _BoardScanScreenState();
}

class _BoardScanScreenState extends State<BoardScanScreen> {
  final _api = BoardScanApi();
  List<Offset> _corners = List.of(initialBoardScanCorners);
  late bool _photo = widget.photo;
  bool _busy = false;
  bool _blackToMove = false;
  bool _flipped = false;
  String? _error;
  BoardScanPosition? _position;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy || !validBoardScanCorners(_corners)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await requireFullAuthGuard(context) || !mounted) return;
      final quadrants = await boardScanQuadrants(
        widget.image,
        _corners,
        photo: _photo,
      );
      if (!mounted) return;
      final position = await _api.scan(quadrants, photo: _photo);
      if (mounted) setState(() => _position = position);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BoardScanException
              ? error.message
              : 'The image could not be read. Try a clearer photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(position == null ? 'Align board' : 'Review position'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(constraints.maxWidth - 48, 560.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (position == null) ...[
                        const Text(
                          'Drag the four corners onto the outer edges of the 64 squares. Leave the frame and coordinates outside.',
                        ),
                        const SizedBox(height: 26),
                        BoardScanCrop(
                          image: widget.image,
                          corners: _corners,
                          enabled: !_busy,
                          onChanged: (corners) =>
                              setState(() => _corners = corners),
                        ),
                        const SizedBox(height: 26),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Diagram')),
                            ButtonSegment(value: true, label: Text('Photo')),
                          ],
                          selected: {_photo},
                          onSelectionChanged: _busy
                              ? null
                              : (v) => setState(() => _photo = v.first),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _corners = const [
                                    Offset.zero,
                                    Offset(1, 0),
                                    Offset(1, 1),
                                    Offset(0, 1),
                                  ],
                                ),
                          child: const Text('Use whole image'),
                        ),
                        if (!validBoardScanCorners(_corners))
                          const Text(
                            'Keep the corners in order around the board.',
                          ),
                        if (_busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          const Text(
                            'Reading the board… You can go back to cancel.',
                          ),
                        ],
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(color: context.colors.danger),
                              semanticsLabel: _error,
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy || !validBoardScanCorners(_corners)
                              ? null
                              : _scan,
                          child: Text(_busy ? 'Reading…' : 'Read position'),
                        ),
                      ] else ...[
                        const Text(
                          'Check every piece against your image. You can fix pieces in the board editor next.',
                        ),
                        const SizedBox(height: 16),
                        BoardScanPreview(
                          size: width,
                          fen: position.fen(),
                          flipped: _flipped,
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => setState(() => _flipped = !_flipped),
                          icon: const Icon(Icons.swap_vert),
                          label: const Text('Flip board'),
                        ),
                        const Text('Side to move'),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('White')),
                            ButtonSegment(value: true, label: Text('Black')),
                          ],
                          selected: {_blackToMove},
                          onSelectionChanged: (v) =>
                              setState(() => _blackToMove = v.first),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Castling and en passant are cleared. Set them in the editor if needed.',
                        ),
                        for (final warning in position.warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              warning,
                              style: TextStyle(color: context.colors.danger),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            context,
                            position.fen(blackToMove: _blackToMove),
                          ),
                          child: const Text('Open in editor'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _position = null;
                            _error = null;
                          }),
                          child: const Text('Adjust crop and retry'),
                        ),
                        const SizedBox(height: 12),
                        Image.memory(widget.image.bytes, fit: BoxFit.contain),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
