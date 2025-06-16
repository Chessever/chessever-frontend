import 'package:flutter/material.dart';

class CompletedEventMenu extends StatelessWidget {
  final VoidCallback? onDownloadTournament;
  final VoidCallback? onAddToLibrary;

  const CompletedEventMenu({
    Key? key,
    this.onDownloadTournament,
    this.onAddToLibrary,
  }) : super(key: key);

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.white),
                  title: const Text(
                    'Download Tournament PGN',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadTournament?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.library_add_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Add to Library',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onAddToLibrary?.call();
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_vert, color: Colors.grey, size: 24),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () => _showMenu(context),
    );
  }
}
