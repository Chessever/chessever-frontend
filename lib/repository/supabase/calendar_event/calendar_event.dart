class CalendarEvent {
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;
  final String? timeControl;
  final DateTime createdAt;
  final String? description;
  final String? imageUrl;
  final String? websiteUrl;
  final String? countryCode;
  final List<dynamic>? players;
  final String? fideEventId;

  CalendarEvent({
    required this.name,
    this.startDate,
    this.endDate,
    this.location,
    this.timeControl,
    required this.createdAt,
    this.description,
    this.imageUrl,
    this.websiteUrl,
    this.countryCode,
    this.players,
    this.fideEventId,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    name: json['name'] as String,
    startDate:
        json['start_date'] == null
            ? null
            : DateTime.parse(json['start_date'] as String),
    endDate:
        json['end_date'] == null
            ? null
            : DateTime.parse(json['end_date'] as String),
    location: json['location'] as String?,
    timeControl: json['time_control'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    websiteUrl: json['website_url'] as String?,
    countryCode: json['country_code'] as String?,
    players: json['players'] as List<dynamic>?,
    fideEventId: json['fide_event_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'start_date': startDate?.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'location': location,
    'time_control': timeControl,
    'created_at': createdAt.toIso8601String(),
    'description': description,
    'image_url': imageUrl,
    'website_url': websiteUrl,
    'country_code': countryCode,
    'players': players,
    'fide_event_id': fideEventId,
  };

  @override
  String toString() =>
      'CalendarEvent($name, location:$location, timeControl:$timeControl, description:$description)';
}
