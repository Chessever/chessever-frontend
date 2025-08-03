// settings_model.dart
class Settings {
  final int id;
  final DateTime createdAt;
  final List<String> liveGroupBroadcastIds;
  final List<String> liveTourIds;
  final List<String> liveRoundIds;

  const Settings({
    required this.id,
    required this.createdAt,
    required this.liveGroupBroadcastIds,
    required this.liveTourIds,
    required this.liveRoundIds,
  });

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    id: json['id'],
    createdAt: DateTime.parse(json['created_at']),
    liveGroupBroadcastIds: List<String>.from(json['live_group_broadcast_ids'] ?? []),
    liveTourIds: List<String>.from(json['live_tour_ids'] ?? []),
    liveRoundIds: List<String>.from(json['live_round_ids'] ?? []),
  );
}