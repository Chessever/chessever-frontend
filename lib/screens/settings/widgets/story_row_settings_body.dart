import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/screens/settings/widgets/start_screen_settings_body.dart'
    show showStartScreenPicker;
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings › Customization: whether the collection stories row sits at
/// the top of Today, On (the default) or Off. One state with the row's own
/// pull past its end, which turns it Off: this row watches it, so it shows
/// the latest choice whichever way it was made, and Today springs the row
/// in or out the moment it changes here. Signed in, the choice is kept on
/// the server with the reader's other settings, so every device follows it.
class StoryRowSettingsBody extends ConsumerWidget {
  const StoryRowSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(storyRowPrefsProvider.select((p) => p.mode));
    return SettingCard(
      key: const ValueKey('settings_story_row'),
      child: SettingsPickerRow(
        title: 'Collection stories',
        caption: 'Key moments from collections, at the top of Today',
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
