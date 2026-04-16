void main() {
  String normalizeFen(String? fen) {
    if (fen == null) return '';
    final parts = fen.trim().split(RegExp(r'\s+'));
    return parts.take(4).join(' ');
  }
  
  String fen1 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  String fen2 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq";
  String fen3 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - -";
  
  print(normalizeFen(fen1));
  print(normalizeFen(fen2));
  print(normalizeFen(fen3));
  
  String robustNormalizeFen(String? fen) {
    if (fen == null) return '';
    final parts = fen.trim().split(RegExp(r'\s+'));
    final board = parts.isNotEmpty ? parts[0] : '';
    final color = parts.length > 1 ? parts[1] : 'w';
    final castling = parts.length > 2 ? parts[2] : '-';
    // en passant usually not important for display equality
    return '$board $color $castling';
  }
  
  print(robustNormalizeFen(fen1));
  print(robustNormalizeFen(fen2));
  print(robustNormalizeFen(fen3));
}
