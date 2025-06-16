import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/settings_service.dart';

enum TimeZone {
  utcMinus12('UTC-12:00', Duration(hours: -12)),
  utcMinus11('UTC-11:00', Duration(hours: -11)),
  utcMinus10('UTC-10:00', Duration(hours: -10)),
  utcMinus9('UTC-09:00', Duration(hours: -9)),
  utcMinus8('UTC-08:00', Duration(hours: -8)),
  utcMinus7('UTC-07:00', Duration(hours: -7)),
  utcMinus6('UTC-06:00', Duration(hours: -6)),
  utcMinus5('UTC-05:00', Duration(hours: -5)),
  utcMinus4('UTC-04:00', Duration(hours: -4)),
  utcMinus3('UTC-03:00', Duration(hours: -3)),
  utcMinus2('UTC-02:00', Duration(hours: -2)),
  utcMinus1('UTC-01:00', Duration(hours: -1)),
  utc('UTC+00:00', Duration(hours: 0)),
  utcPlus1('UTC+01:00', Duration(hours: 1)),
  utcPlus2('UTC+02:00', Duration(hours: 2)),
  utcPlus3('UTC+03:00', Duration(hours: 3)),
  utcPlus4('UTC+04:00', Duration(hours: 4)),
  utcPlus5('UTC+05:00', Duration(hours: 5)),
  utcPlus6('UTC+06:00', Duration(hours: 6)),
  utcPlus7('UTC+07:00', Duration(hours: 7)),
  utcPlus8('UTC+08:00', Duration(hours: 8)),
  utcPlus9('UTC+09:00', Duration(hours: 9)),
  utcPlus10('UTC+10:00', Duration(hours: 10)),
  utcPlus11('UTC+11:00', Duration(hours: 11)),
  utcPlus12('UTC+12:00', Duration(hours: 12));

  final String display;
  final Duration offset;

  const TimeZone(this.display, this.offset);
}

class TimezoneNotifier extends StateNotifier<TimeZone> {
  TimezoneNotifier() : super(TimeZone.utc) {
    // Load saved timezone when initialized
    _loadSavedTimezone();
  }

  Future<void> _loadSavedTimezone() async {
    final savedTimezone = await SettingsService.loadTimezone();
    if (savedTimezone != null) {
      state = savedTimezone;
    }
  }

  void setTimezone(TimeZone timezone) {
    state = timezone;
    _saveTimezone();
  }

  Future<void> _saveTimezone() async {
    await SettingsService.saveTimezone(state);
  }
}

final timezoneProvider = StateNotifierProvider<TimezoneNotifier, TimeZone>((
  ref,
) {
  return TimezoneNotifier();
});
