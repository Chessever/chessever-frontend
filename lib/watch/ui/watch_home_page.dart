import 'package:flutter/cupertino.dart';
import '../watch_controller.dart';
import 'watch_event_pages.dart';
import 'watch_widgets.dart';

class WatchHomePage extends StatelessWidget {
  const WatchHomePage({super.key, required this.controller});
  final WatchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => WatchPage(
      title: 'Current',
      root: true,
      onRefresh: controller.loading ? null : () => controller.refresh(),
      children: [
        if (controller.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        if (controller.error != null) WatchNote(controller.error!),
        if (!controller.loading &&
            controller.error == null &&
            controller.visibleEvents.isEmpty)
          WatchNote(
            controller.favoritesOnly
                ? 'No followed events on this page.'
                : 'No current events. Check back soon.',
          ),
        for (final event in controller.visibleEvents)
          WatchRow(
            label: event.name,
            detail: event.timeControl == 'standard'
                ? 'Classical'
                : event.timeControl,
            trailing: controller.account.followsEvent(event.id, event.name)
                ? const Icon(
                    CupertinoIcons.star_fill,
                    semanticLabel: 'Followed on iPhone',
                    size: 14,
                    color: WatchStyle.ink,
                  )
                : null,
            onTap: () => watchPush(context, watchEventPage(controller, event)),
          ),
        if (controller.hasMore &&
            !controller.loading &&
            controller.error == null)
          WatchRow(
            label: 'More current events',
            onTap: () => controller.refresh(more: true),
          ),
        WatchRow(
          label: 'My iPhone',
          icon: CupertinoIcons.device_phone_portrait,
          detail: controller.account.signedIn
              ? 'Account connected'
              : 'Connect your account',
          onTap: () =>
              watchPush(context, WatchAccountPage(controller: controller)),
        ),
        if (controller.account.signedIn)
          WatchRow(
            label: controller.favoritesOnly
                ? 'Show all current events'
                : 'Show followed events',
            icon: controller.favoritesOnly
                ? CupertinoIcons.list_bullet
                : CupertinoIcons.star,
            onTap: controller.toggleFavorites,
          ),
        if (controller.updatedAt != null)
          WatchNote(
            'Updated '
            '${controller.updatedAt!.hour.toString().padLeft(2, '0')}:'
            '${controller.updatedAt!.minute.toString().padLeft(2, '0')}',
          ),
      ],
    ),
  );
}

class WatchAccountPage extends StatefulWidget {
  const WatchAccountPage({super.key, required this.controller});
  final WatchController controller;
  @override
  State<WatchAccountPage> createState() => _WatchAccountPageState();
}

class _WatchAccountPageState extends State<WatchAccountPage> {
  String? _message;
  bool _busy = false;
  Future<void> _sync() async {
    setState(() => _busy = true);
    final sent = await widget.controller.requestSync();
    if (mounted) {
      setState(() {
        _busy = false;
        _message = sent
            ? 'Sync requested. iPhone updates arrive automatically.'
            : 'Open ChessEver on your paired iPhone, then try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final account = widget.controller.account;
      final connection = widget.controller.connection;
      return WatchPage(
        title: 'My iPhone',
        children: [
          WatchNote(
            account.signedIn ? account.name : 'Sign in to ChessEver on iPhone.',
          ),
          WatchRow(
            label: connection.reachable
                ? 'iPhone connected'
                : 'iPhone unavailable',
            detail: connection.counterpartInstalled
                ? 'ChessEver companion installed'
                : 'Install ChessEver on your paired iPhone',
          ),
          if (account.signedIn) ...[
            WatchRow(
              label: 'Favorites from iPhone',
              detail: '${account.playerNames.length} followed players',
            ),
            const WatchNote(
              'Alerts mirror your iPhone. Manage permissions in '
              'Watch → Notifications → ChessEver.',
            ),
            for (final entry in const {
              'favorite_event_alerts': 'Event alerts',
              'favorite_player_alerts': 'Player alerts',
              'heads_up_alerts': 'Round reminders',
            }.entries)
              WatchRow(
                label: entry.value,
                detail: account.preferences.containsKey(entry.key)
                    ? (account.preferences[entry.key]!
                          ? 'On · managed on iPhone'
                          : 'Off · managed on iPhone')
                    : 'Managed on iPhone',
              ),
            WatchNote(
              'Account synced ${DateTime.fromMicrosecondsSinceEpoch(account.revision).toLocal().hour.toString().padLeft(2, '0')}:'
              '${DateTime.fromMicrosecondsSinceEpoch(account.revision).toLocal().minute.toString().padLeft(2, '0')}',
            ),
          ],
          WatchRow(
            label: _busy ? 'Requesting…' : 'Sync with iPhone',
            icon: CupertinoIcons.refresh,
            onTap: _busy ? null : _sync,
          ),
          if (_message != null) WatchNote(_message!),
        ],
      );
    },
  );
}
