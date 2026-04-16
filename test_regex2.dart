void main() {
  final regex = RegExp(r'\[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\]');
  
  void test(String s) {
    final match = regex.firstMatch(s);
    if (match != null) {
      final hours = match.group(1) ?? '';
      final rest = match.group(2) ?? '';
      print(s + ' -> ' + hours + rest);
    } else {
      print(s + ' -> null');
    }
  }
  
  test('[%clk 1:23:45]');
  test('[%clk 12:34]');
  test('[%clk 0:03:00.000]');
  test('[%clk 0:00:15.5]');
}
