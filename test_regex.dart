void main() {
  final regex = RegExp(r'\[%clk (\d+:\d+:\d+)\]');
  print(regex.firstMatch('[%clk 1:23:45]')?.group(1));
  print(regex.firstMatch('[%clk 12:34]')?.group(1));
  print(regex.firstMatch('[%clk 0:03:00.000]')?.group(1));
}
