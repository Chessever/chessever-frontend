void main() {
  String fen1 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  String fen2 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq";
  
  String normalizeFen1(String fen) => fen.split(' ').take(4).join(' ');
  String normalizeFen2(String? fen) {
    if (fen == null) return '';
    return fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
  }
  
  print(normalizeFen1(fen1));
  print(normalizeFen2(fen1));
  
  print(normalizeFen1(fen2));
  print(normalizeFen2(fen2));
  
  print(normalizeFen1(fen1) == normalizeFen1(fen2));
  print(normalizeFen2(fen1) == normalizeFen2(fen2));
}
