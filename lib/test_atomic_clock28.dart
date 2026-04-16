void main() {
  String normalizeFen(String? fen) {
    if (fen == null) return '';
    return fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
  }
  
  String f1 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  String f2 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";
  
  print(normalizeFen(f1));
  print(normalizeFen(f2));
}
