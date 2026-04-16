void main() {
  final regex = RegExp(r'\[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\]');
  void test(String comment) {
    final timeMatch = regex.firstMatch(comment);
    if (timeMatch != null) {
      final hours = timeMatch.group(1) ?? '';
      final rest = timeMatch.group(2) ?? '';
      print("-> " + hours + rest);
    } else {
      print('no match');
    }
  }
  
  test('[%clk 1:00:00]');
  test('[%clk 0:59:58]');
  test('[%clk 0:03:00]');
  test('[%clk 0:00:15.5]');
  test('[%clk 12:34]');
}
