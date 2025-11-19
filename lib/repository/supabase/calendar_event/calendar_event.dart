class CalendarEvent {
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;
  final String? timeControl;
  final DateTime createdAt;

  CalendarEvent({
    required this.name,
    this.startDate,
    this.endDate,
    this.location,
    this.timeControl,
    required this.createdAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        name: json['name'] as String,
        startDate: json['start_date'] == null
            ? null
            : DateTime.parse(json['start_date'] as String),
        endDate: json['end_date'] == null
            ? null
            : DateTime.parse(json['end_date'] as String),
        location: json['location'] as String?,
        timeControl: json['time_control'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'location': location,
        'time_control': timeControl,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  String toString() =>
      'CalendarEvent($name, location:$location, timeControl:$timeControl)';
}
