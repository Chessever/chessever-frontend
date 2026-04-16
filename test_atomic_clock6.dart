void main() {
  String _formatTimeFromSeconds(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '00:00';
    }

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return minutes.toString().padLeft(2, '0') + ':' + seconds.toString().padLeft(2, '0');
  }
  
  print(_formatTimeFromSeconds(179));
  print(_formatTimeFromSeconds(15));
}
