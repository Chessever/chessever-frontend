/// Sentinel identity for gamebase-only "virtual" events rendered inside the
/// real tournament detail screen. Kept dependency-free (no model/repository
/// imports) so widely-imported files like `games_tour_model.dart` can use it
/// without creating an import cycle.
library;

const String _virtualPrefix = 'gamebase::';

String virtualBroadcastId(String eventName) =>
    '$_virtualPrefix${eventName.trim()}';

bool isVirtualGamebaseId(String? id) =>
    id != null && id.startsWith(_virtualPrefix);

String? eventNameFromVirtualId(String? id) =>
    isVirtualGamebaseId(id) ? id!.substring(_virtualPrefix.length) : null;
