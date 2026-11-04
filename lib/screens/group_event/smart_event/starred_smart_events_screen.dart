import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/smart_event_mutation.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> openStarredSmartEvents(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StarredSmartEventsScreen()),
    );

/// Lists actual subscriptions, including ones deliberately removed from My
/// Space. Reading never pins, migrates, deletes or subscribes anything.
class StarredSmartEventsScreen extends ConsumerWidget {
  const StarredSmartEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteEventsProvider);
    final pins = ref.watch(spaceShortcutsProvider);
    final busy = ref.watch(smartEventMutationBusyProvider);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Starred Smart Events'),
        actions: [
          IconButton(
            tooltip: 'Refresh subscriptions',
            icon: const Icon(Icons.refresh),
            onPressed: busy
                ? null
                : () async {
                    try {
                      await ref
                          .read(favoriteEventsProvider.notifier)
                          .readForSmartEventEdit();
                    } catch (_) {
                      if (context.mounted) {
                        showAppSnack(
                          context,
                          'Could not refresh subscriptions. Please retry.',
                          tone: AppSnackTone.danger,
                        );
                      }
                    }
                  },
          ),
        ],
      ),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () =>
                ref.read(favoriteEventsProvider.notifier).refresh(),
            child: const Text('Could not load subscriptions. Retry'),
          ),
        ),
        data: (rows) {
          final byCriteria = <String, SmartEventRequest>{};
          final names = <String, String>{};
          for (final row in rows.where(isSmartFavoriteEvent)) {
            final request = SmartEventRequest.fromFavoriteEvent(row);
            byCriteria.putIfAbsent(request.criteriaKey, () => request);
            names.putIfAbsent(request.criteriaKey, () => row.eventName);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Starring subscribes to new-game notifications. Unstar to stop them. Removing a card from My Space does not unsubscribe.',
              ),
              const SizedBox(height: 12),
              if (byCriteria.isEmpty) const Text('No starred Smart Events.'),
              for (final request in byCriteria.values) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(names[request.criteriaKey]!),
                  subtitle: Text(smartEventSubscriptionCriteriaLabel(request)),
                  trailing: SmartEventStar(request: request),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SmartEventScreen(request: request),
                    ),
                  ),
                ),
                if (pins.isLoading)
                  const Text('Loading My Space…')
                else if (pins.hasError)
                  const Text('My Space unavailable. Retry from My Space.')
                else if (!pins.requireValue.any(
                  (s) => s.key == smartEventSpaceDraft(request).key,
                ))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: Text(
                        'Add ${names[request.criteriaKey]} to My Space',
                      ),
                      onPressed: busy
                          ? null
                          : () => toggleSpaceShortcut(
                              context: context,
                              ref: ref,
                              draft: smartEventSpaceDraft(
                                request,
                              ).copyWith(title: names[request.criteriaKey]),
                            ),
                    ),
                  )
                else
                  const Text('In My Space'),
                const Divider(),
              ],
            ],
          );
        },
      ),
    );
  }
}

String smartEventSubscriptionCriteriaLabel(SmartEventRequest request) {
  final formats = request.formatsAndStates.toList()..sort();
  final pace = formats
      .where(const {'standard', 'rapid', 'blitz'}.contains)
      .join(', ');
  final state = formats.where(const {'live', 'completed'}.contains).join(', ');
  return '${request.minElo}–${request.maxElo} average rating · '
      '${pace.isEmpty ? 'All time controls' : pace} · '
      '${state.isEmpty ? 'Live and completed' : state} · '
      '${request.eco.isAll ? 'All openings' : request.eco.displayText}';
}
