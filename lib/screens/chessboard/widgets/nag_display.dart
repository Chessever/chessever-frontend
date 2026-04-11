import 'package:flutter/material.dart';

class NagDisplay {
  final String symbol;
  final Color? color;
  const NagDisplay(this.symbol, this.color);
}

NagDisplay? getNagDisplay(int nag) {
  switch (nag) {
    case 1: return const NagDisplay('!', Color(0xFF177A68)); // Good
    case 2: return const NagDisplay('?', Color(0xFFEB9518)); // Mistake
    case 3: return const NagDisplay('!!', Color(0xFF177A68)); // Brilliant
    case 4: return const NagDisplay('??', Color(0xFFC9342E)); // Blunder
    case 5: return const NagDisplay('!?', Color(0xFFFABE46)); // Speculative (Interesting)
    case 6: return const NagDisplay('?!', Color(0xFFFABE46)); // Questionable (Inaccuracy)
    case 7: return const NagDisplay('□', null); // Forced move
    case 10: return const NagDisplay('=', null); // Drawish
    case 13: return const NagDisplay('∞', null); // Unclear
    case 14: return const NagDisplay('⩲', null); // White is slightly better
    case 15: return const NagDisplay('⩱', null); // Black is slightly better
    case 16: return const NagDisplay('±', null); // White is better
    case 17: return const NagDisplay('∓', null); // Black is better
    case 18: return const NagDisplay('+-', null); // White is winning
    case 19: return const NagDisplay('-+', null); // Black is winning
    case 22: return const NagDisplay('⨀', null); // Zugzwang
    case 32: return const NagDisplay('⟳', null); // Development advantage
    case 36: return const NagDisplay('→', null); // Initiative
    case 40: return const NagDisplay('↑', null); // Attack
    case 44: return const NagDisplay('=', null); // Compensation
    case 132: return const NagDisplay('⇆', null); // Counterplay
    case 140: return const NagDisplay('∆', null); // With the idea
    case 146: return const NagDisplay('N', null); // Novelty
    default: return null;
  }
}
