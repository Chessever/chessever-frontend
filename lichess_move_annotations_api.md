# Lichess Move Annotations API - Frontend Implementation Guide

## Overview

This document describes how to fetch move quality annotations (blunders, mistakes, inaccuracies) from Lichess API for display in the app.

## API Endpoint

```
GET https://lichess.org/game/export/{gameId}
```

## Required Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `evals` | `true` | Includes the `analysis` array with evaluations and judgments |

## Required Headers

| Header | Value | Description |
|--------|-------|-------------|
| `Accept` | `application/json` | Returns JSON format (not PGN) |

## Example Request

```http
GET https://lichess.org/game/export/q7ZvsdUF?evals=true
Accept: application/json
```

## Response Structure

```json
{
  "id": "q7ZvsdUF",
  "rated": true,
  "variant": "standard",
  "speed": "blitz",
  "status": "resign",
  "players": {
    "white": {
      "user": { "name": "player1", "id": "player1" },
      "rating": 1500,
      "analysis": {
        "inaccuracy": 2,
        "mistake": 1,
        "blunder": 1,
        "accuracy": 85
      }
    },
    "black": {
      "user": { "name": "player2", "id": "player2" },
      "rating": 1520,
      "analysis": {
        "inaccuracy": 3,
        "mistake": 0,
        "blunder": 2,
        "accuracy": 78
      }
    }
  },
  "moves": "e4 e5 Nf3 Nc6 Bb5 a6 ...",
  "analysis": [
    { "eval": 17 },
    { "eval": 27 },
    { "eval": 18 },
    { "eval": 364, "judgment": { "name": "Blunder", "comment": "Blunder. Rfe8 was best." } },
    { "eval": -1, "judgment": { "name": "Mistake", "comment": "Mistake. g3 was best." } },
    { "eval": 122, "judgment": { "name": "Inaccuracy", "comment": "Inaccuracy. Qxe6 was best." } }
  ]
}
```

## Key Fields

### `analysis` Array (per-move)

Each element corresponds to a move in the `moves` string (index 0 = first move, index 1 = second move, etc.).

| Field | Type | Description |
|-------|------|-------------|
| `eval` | `int` | Centipawn evaluation (100 = 1 pawn advantage for white, negative = black advantage) |
| `mate` | `int?` | Present instead of `eval` when mate is found. Positive = white mates in N, negative = black mates in N |
| `judgment` | `object?` | **Only present when the move is an error** |
| `judgment.name` | `string` | One of: `"Inaccuracy"`, `"Mistake"`, `"Blunder"` |
| `judgment.comment` | `string` | Human-readable description, e.g., `"Blunder. Nxg6 was best."` |

### `players.{color}.analysis` (per-player summary)

| Field | Type | Description |
|-------|------|-------------|
| `inaccuracy` | `int` | Count of inaccuracies |
| `mistake` | `int` | Count of mistakes |
| `blunder` | `int` | Count of blunders |
| `accuracy` | `int` | Accuracy percentage (0-100) |

## Annotation Symbols Mapping

| API Value | Symbol | Color (suggested) |
|-----------|--------|-------------------|
| `Inaccuracy` | `?!` | Yellow |
| `Mistake` | `?` | Orange |
| `Blunder` | `??` | Red |

## Important Notes

1. **Analysis may not exist**: Not all games have computer analysis. Check if `analysis` field exists before accessing.

2. **Index mapping**: The `analysis` array index matches the move index in the `moves` string (split by space).

3. **Only errors have judgment**: Moves without errors will only have `eval` (or `mate`), no `judgment` field.

4. **Rate limiting**: Lichess API has rate limits. For bulk fetching, use `/api/games/user/{username}` or `/api/games/export/_ids` instead.

## Dart Model Example

```dart
class MoveAnalysis {
  final int? eval;
  final int? mate;
  final MoveJudgment? judgment;

  MoveAnalysis({this.eval, this.mate, this.judgment});

  factory MoveAnalysis.fromJson(Map<String, dynamic> json) {
    return MoveAnalysis(
      eval: json['eval'] as int?,
      mate: json['mate'] as int?,
      judgment: json['judgment'] != null
          ? MoveJudgment.fromJson(json['judgment'])
          : null,
    );
  }

  bool get isBlunder => judgment?.name == 'Blunder';
  bool get isMistake => judgment?.name == 'Mistake';
  bool get isInaccuracy => judgment?.name == 'Inaccuracy';
  bool get hasError => judgment != null;
}

class MoveJudgment {
  final String name; // "Inaccuracy", "Mistake", "Blunder"
  final String comment;

  MoveJudgment({required this.name, required this.comment});

  factory MoveJudgment.fromJson(Map<String, dynamic> json) {
    return MoveJudgment(
      name: json['name'] as String,
      comment: json['comment'] as String,
    );
  }
}

class PlayerAnalysisSummary {
  final int inaccuracy;
  final int mistake;
  final int blunder;
  final int accuracy;

  PlayerAnalysisSummary({
    required this.inaccuracy,
    required this.mistake,
    required this.blunder,
    required this.accuracy,
  });

  factory PlayerAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return PlayerAnalysisSummary(
      inaccuracy: json['inaccuracy'] as int,
      mistake: json['mistake'] as int,
      blunder: json['blunder'] as int,
      accuracy: json['accuracy'] as int,
    );
  }
}
```

## API Call Example (Dart/http)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>?> fetchGameWithAnalysis(String gameId) async {
  final response = await http.get(
    Uri.parse('https://lichess.org/game/export/$gameId?evals=true'),
    headers: {'Accept': 'application/json'},
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  return null;
}
```
