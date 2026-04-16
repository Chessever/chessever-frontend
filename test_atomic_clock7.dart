import 'package:flutter/material.dart';

void main() {
  String _formatTimeFromSeconds(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '00:00';
    }

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return minutes.toString().padLeft(2, '0') + ':' + seconds.toString().padLeft(2, '0');
  }

  String _formatTimeWithHours(String timeString) {
    if (timeString.contains('h') ||
        timeString.contains(':') && timeString.split(':').length == 3) {
      return timeString;
    }

    final timeParts = timeString.split(':');
    if (timeParts.length != 2) {
      return timeString; 
    }

    try {
      final minutes = int.parse(timeParts[0]);
      final seconds = int.parse(timeParts[1]);

      if (minutes < 60) {
        return timeString;
      }

      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      return hours.toString().padLeft(2, '0') + ':' + remainingMinutes.toString().padLeft(2, '0') + ':' + seconds.toString().padLeft(2, '0');
    } catch (e) {
      return timeString; 
    }
  }
  
  print(_formatTimeWithHours(_formatTimeFromSeconds(179)));
  print(_formatTimeWithHours(_formatTimeFromSeconds(3615)));
}
