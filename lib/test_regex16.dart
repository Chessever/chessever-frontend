void main() {
  String fen1 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  String fen2 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";
  
  String normalizeFen(String? fen) {
    if (fen == null) return '';
    return fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
  }
  
  print(normalizeFen(fen1));
  print(normalizeFen(fen2));
  print(normalizeFen(fen1) == normalizeFen(fen2));
}
