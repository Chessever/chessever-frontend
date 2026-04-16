void main() {
  String timeString = "00:00:15";
  int totalSeconds = 0;
  final timeParts = timeString.split(':');
  if (timeParts.length == 2) {
    // MM:SS format
    final minutes = int.parse(timeParts[0]);
    final seconds = int.parse(timeParts[1]);
    totalSeconds = minutes * 60 + seconds;
  } else if (timeParts.length == 3) {
    // HH:MM:SS format
    final hours = int.parse(timeParts[0]);
    final minutes = int.parse(timeParts[1]);
    final seconds = int.parse(timeParts[2]);
    totalSeconds = hours * 3600 + minutes * 60 + seconds;
  }
  print(totalSeconds);
  
  timeString = "0:02:59";
  final parts = timeString.split(':');
  if (parts.length == 3) {
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(parts[2]);
    print(hours * 3600 + minutes * 60 + seconds);
  }
}
