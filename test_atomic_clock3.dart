void main() {
  String timeString = "0:02:59";
  int _parseTimeToSeconds(String timeString) {
    try {
      // Handle 1h23m format
      if (timeString.contains('h') && timeString.contains('m')) {
        final hourMatch = RegExp(r'(\d+)h').firstMatch(timeString);
        final minuteMatch = RegExp(r'(\d+)m').firstMatch(timeString);

        final hours = hourMatch != null ? int.parse(hourMatch.group(1)!) : 0;
        final minutes =
            minuteMatch != null ? int.parse(minuteMatch.group(1)!) : 0;

        return hours * 3600 + minutes * 60;
      }

      // Handle HH:MM:SS or MM:SS format
      final timeParts = timeString.split(':');
      if (timeParts.length == 2) {
        // MM:SS format
        final minutes = int.parse(timeParts[0]);
        final seconds = int.parse(timeParts[1]);
        return minutes * 60 + seconds;
      } else if (timeParts.length == 3) {
        // HH:MM:SS format
        final hours = int.parse(timeParts[0]);
        final minutes = int.parse(timeParts[1]);
        final seconds = int.parse(timeParts[2]);
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (e) {
      // Return 0 if parsing fails
    }
    return 0;
  }
  
  print(_parseTimeToSeconds("0:02:59"));
  print(_parseTimeToSeconds("0:00:15"));
}
