import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlayerStandingSectionSelect extends ConsumerWidget {
  const PlayerStandingSectionSelect({
    super.key,
    required this.tourId,
    required this.sections,
  });
  final String tourId;
  final List<OfficialPlayerSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = selectedOfficialPlayerSection(
      sections,
      ref.watch(selectedPlayerStandingSectionProvider(tourId)),
    );
    if (section == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      // DropdownButtonFormField's field, with the glass menu.
      child: GlassDropdown<String>(
        key: ValueKey('standing-section:$tourId'),
        value: section.id,
        isExpanded: true,
        isDense: true,
        decoration: const InputDecoration(labelText: 'Official section'),
        items: [
          for (final item in sections)
            DropdownMenuItem(value: item.id, child: Text(item.name)),
        ],
        onChanged: (id) {
          if (id != null) {
            ref
                    .read(
                      selectedPlayerStandingSectionProvider(tourId).notifier,
                    )
                    .state =
                id;
          }
        },
      ),
    );
  }
}
