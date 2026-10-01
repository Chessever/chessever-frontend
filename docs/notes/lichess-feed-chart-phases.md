# Lichess phase boundaries for the feed chart

Verified against official sources on 2026-09-30. The Flutter app renders server-supplied division values; its chart does not calculate game phases. The server delegates calculation to scalachess.

## Sources

- [Lichess Flutter evaluation chart](https://github.com/lichess-org/mobile/blob/e57fcb4114f8ca3b9c35991033a972c9ba3bae7a/lib/src/widgets/acpl_chart.dart)
- [Server division caller](https://github.com/lichess-org/lila/blob/36bc95356785ae99322691837c52f310f6138738/modules/game/src/main/Divider.scala)
- [Scalachess calculation](https://github.com/lichess-org/scalachess/blob/57d3483/core/src/main/scala/Divider.scala)
- [Scalachess replay board construction](https://github.com/lichess-org/scalachess/blob/57d3483/core/src/main/scala/CanPlay.scala#L242-L252)
- [Official algorithm tests](https://github.com/lichess-org/scalachess/blob/57d3483/test-kit/src/test/scala/DividerTest.scala)
- [Web chart phase rendering](https://github.com/lichess-org/lila/blob/36bc95356785ae99322691837c52f310f6138738/ui/chart/src/division.ts)

## Exact calculation

Supply the initial board followed by every board after each legal mainline half-move, including the final board. Enumerate this sequence from zero. Consequently board index 0 is the initial position and index N is the position after N relative plies. This remains relative to the supplied initial FEN, rather than its fullmove counter.

Find the first board satisfying any of these conditions:

1. The combined count of queens, rooks, bishops and knights is at most 10.
2. White has fewer than four pieces of any role on rank 1, or Black has fewer than four pieces of any role on rank 8.
3. Mixedness is strictly greater than 150.

That index is the candidate middlegame boundary. Only when a candidate exists, find the first board with at most six combined queens, rooks, bishops and knights: that is the endgame boundary. Scan from the beginning for both boundaries. Keep the middlegame boundary only if no endgame exists or middlegame is strictly earlier than endgame. If they coincide, retain endgame alone. Boundaries can legitimately be zero; absence must not be confused with zero.

No fixed move numbers, engine score, opening database lookup or queen-exchange shortcut participates in this algorithm.

### Mixedness

Sum a score for every overlapping 2-by-2 region of the board: seven file origins times seven rank origins, 49 regions total. Count all White and Black pieces in each region, including pawns and kings. Let `y` be the region's lower rank, 1 through 7; let `w` and `b` be the two counts. The table below gives the exact contribution. All unspecified cases score zero.

| White count | Black 0 | Black 1 | Black 2 | Black 3 | Black 4 |
|---|---|---|---|---|---|
| 0 | 0 | `1+y` | `y<6 ? 8-y : 0` | `y<7 ? 10-y : 0` | `y<7 ? 10-y : 0` |
| 1 | `9-y` | `5+abs(4-y)` | `11-y` | `12-y` | 0 |
| 2 | `y>2 ? y : 0` | `3+y` | 7 | 0 | 0 |
| 3 | `y>1 ? 2+y : 0` | `4+y` | 0 | 0 | 0 |
| 4 | `y>1 ? 2+y : 0` | 0 | 0 | 0 | 0 |

### Chart indexing and labels

The Flutter chart's evaluations start after the first move. Its evaluation spot zero therefore represents relative ply 1, and it renders a positive boundary at `boundary - 1`. Zero boundaries render at x=0. Its current-position cursor similarly uses `currentNodePly - 1 - rootPly`.

A feed chart whose x=0 represents the initial board must instead draw boundaries at the relative board indices directly. Do not copy the mobile `-1` offset into that chart.

The Flutter chart adds Opening at x=0 when a positive middlegame boundary exists, then Middlegame at that boundary. If middlegame is zero, it adds Middlegame at zero. It adds Endgame when an endgame boundary exists. It does not invent phase boundaries for short games that never satisfy the calculation. Labels are vertical, placed at the top beside the corresponding line.

Current mobile and web sources draw solid vertical phase lines; dashed lines are the requested ChessEver visual treatment, with the same calculated positions.

The server only classifies variants where these heuristics make sense: Standard, Chess960, ThreeCheck, KingOfTheHill and FromPosition. Other variants return empty division. Invalid replay also returns empty division.

## Source licenses

[Scalachess is MIT](https://github.com/lichess-org/scalachess/blob/57d3483/LICENSE), copyright 2012-2014 Thibault Duplessis. Preserve its copyright and complete MIT permission notice alongside a translation or substantial adaptation of the calculation. [Lichess mobile is GPLv3](https://github.com/lichess-org/mobile/blob/e57fcb4114f8ca3b9c35991033a972c9ba3bae7a/LICENSE); use its behavior as a reference and implement the ChessEver chart independently rather than copying its widget source.
