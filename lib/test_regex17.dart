void main() {
  String normalizeFen(String fen) => fen.split(' ').take(4).join(' ');
  print(normalizeFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"));
  print(normalizeFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"));
}
