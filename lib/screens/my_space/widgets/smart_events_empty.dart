import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SmartEventsEmpty extends ConsumerWidget {
  const SmartEventsEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360.w),
        child: AppButton(
          key: const ValueKey('smart_events_empty_add'),
          text: 'Create Smart Event',
          onPressed: () => openSpaceAdd(context, ref, SpaceSection.smartEvents),
        ),
      ),
    ),
  );
}
