void main() {
  String timeStr = '0:59:58';
  final parts = timeStr.split(':');
  print(parts.length == 3);
}
