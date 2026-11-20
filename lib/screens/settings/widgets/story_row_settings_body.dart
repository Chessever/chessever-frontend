import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/screens/settings/widgets/start_screen_settings_body.dart'
    show showStartScreenPicker;
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings › Customization: when the collection stories row sits at the
/// top of Today. The choice follows the reader's account; Today springs the
/// row in or out the moment it changes.
class StoryRowSettingsBody extends ConsumerWidget {
  const StoryRowSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(storyRowPrefsProvider.select((p) => p.mode));
    return SettingCard(
      key: const ValueKey('settings_story_row'),
      child: SettingsPickerRow(
        title: 'Collection stories',
        caption: 'The circles at the top of Today',
        value: mode.shortLabel,
        onTap: () async {
          final picked = await showStartScreenPicker<StoryRowMode>(
            context: context,
            title: 'Collection stories',
            options: StoryRowMode.values,
            label: (mode) => mode.label,
            selected: mode,
          );
          if (picked == null || picked == mode) return;
          await ref.read(storyRowPrefsProvider.notifier).setMode(picked);
          HapticFeedbackService.success();
        },
      ),
    );
  }
}
