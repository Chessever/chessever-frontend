# Gamebase API Guide

This document provides a comprehensive guide to the **Gamebase API**, a powerful chess database engine that allows you to query players, games, and positions with advanced filtering, sorting, and search capabilities.

## Base URL
- **Production**: `https://service.chessever.com`
- **Development**: `http://localhost:3232`

## Authentication
All API requests must include the `X-API-Key` header.

```http
X-API-Key: <your-api-key>
```

---

## 1. Global Search
*End-to-end full-text search across the entire database.*

### **Universal Search**
**Endpoint:** `GET /api/search`

Use this for a "Google-like" search bar experience. It searches across multiple resources (Players, Games) simultaneously.

**Parameters:**
- `q` (required): The search string (e.g., "Carlsen", "Kasparov", a generic UUID).
- `pageNumber`: Page number (default: 1).
- `pageSize`: Results per page (default: 20).

**Example Request:**
```http
GET /api/search?q=Carlsen
```

**Response:**
Returns a mixed list of results with a `resource` type ("player" or "game"), a match `score`, and a preview snippet.

---

## 2. Advanced Querying (The Powerhouse)
*Complex filtering, sorting, and specific resource querying.*

### **Metadata Discovery**
**Endpoint:** `GET /api/search/metadata`

Before building a complex query UI, call this endpoint to discover exactly what fields are available for filtering and sorting on each resource.

**Response Example:**
```json
{
  "resources": [
    {
      "name": "player",
      "columns": [
        { "name": "ratingClassical", "type": "integer", "operators": ["eq", "gte", "lte", "between"] },
        { "name": "fed", "type": "string", "operators": ["eq", "in"] }
      ]
    }
  ]
}
```

### **Structured Query**
**Endpoint:** `POST /api/search/query`

This is the most powerful endpoint. It supports recursive boolean logic (`AND`, `OR`, `NOT`) for filtering.

**Body Parameters:**
- `resource`: Target resource (`player` or `game`).
- `q`: Optional free-text search string for simple matches.
- `where`: A structured filter object.
- `orderBy`: Array of sorting rules.
- `pageNumber` / `pageSize`: Pagination.

#### **Use Case Examples:**

**A. Find High-Rated Norwegian Players**
*Find players from Norway ("NOR") with a Classical rating above 2700.*

```json
{
  "resource": "player",
  "where": {
    "and": [
      { "field": "fed", "op": "eq", "value": "NOR" },
      { "field": "ratingClassical", "op": "gt", "value": 2700 }
    ]
  },
  "orderBy": [
    { "field": "ratingClassical", "direction": "desc" }
  ]
}
```

**B. Find Specific Games**
*Find all Classical games played by "White" that ended in a Draw ("D") after 2023.*

```json
{
  "resource": "game",
  "where": {
    "and": [
      { "field": "timeControl", "op": "eq", "value": "CLASSICAL" },
      { "field": "result", "op": "eq", "value": "D" },
      { "field": "date", "op": "gte", "value": "2023-01-01T00:00:00Z" }
    ]
  },
  "orderBy": [
    { "field": "date", "direction": "desc" }
  ]
}
```

---

## 3. Player Management

### **Search Players**
**Endpoint:** `GET /api/player`

A dedicated lightweight endpoint for listing and searching players.

**Parameters:**
- `name`: Partial name match (case-insensitive).
- `pageNumber` / `pageSize`: Pagination.

### **Get Player Details**
**Endpoint:** `GET /api/player/{id}`

Retrieve full details for a single player by their UUID, including all rating categories (Classical, Rapid, Blitz) and FIDE ID.

---

## 4. Game & Position Analysis

### **Get Game Details**
**Endpoint:** `GET /api/game/{id}`

Retrieve the full record of a game, including the move list (PGN/JSON data), players, result, and date.

### **Position Analytics (Opening Explorer)**
**Endpoint:** `GET /api/game-position/aggregates`

This endpoint powers "Opening Explorer" features. It tells you what moves have been played from a specific board position and their win rates.

**Parameters:**
- `fen` (required): The board position in FEN notation.
- `playerId`: (Optional) Limit stats to a specific player's games.
- `timeControl`: (Optional) Filter by `CLASSICAL`, `RAPID`, or `BLITZ`.
- `minRating` / `maxRating`: (Optional) Filter games by player rating range.

**Example Request:**
```http
GET /api/game-position/aggregates?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1&minRating=2500
```

**Response:**
Returns a list of candidate moves from that position.
```json
{
  "status": "success",
  "data": {
    "moves": [
      { "uci": "e2e4", "white": 1200, "black": 900, "draws": 800, "total": 2900 },
      { "uci": "d2d4", "white": 1100, "black": 850, "draws": 950, "total": 2900 }
    ]
  }
}
```

---

## 5. Flutter / Dart Implementation Guide

To consume this API in your Flutter application, we recommend using `dio` for HTTP requests and `dart_mappable` for simplified data modeling.

### **1. Setup**
Add dependencies to your `pubspec.yaml`:
```yaml
dependencies:
  dio: ^5.0.0
  dart_mappable: ^4.0.0

dev_dependencies:
  build_runner: ^2.3.0
  dart_mappable_builder: ^4.0.0
```

### **2. API Client Helper**
Create a helper class to handle authentication and base URL structure.
```dart
import 'package:dio/dio.dart';

class GamebaseApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://service.chessever.com/api',
    // Add your key here, or better, via an environment config
    headers: {'X-API-Key': 'YOUR_API_KEY'}, 
  ));

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } catch (e) {
      if (e is DioException) {
        // Handle standard API errors (401, 404, etc.)
        throw Exception(e.response?.data['error']['message'] ?? 'Unknown API Error');
      }
      rethrow;
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    return await _dio.post(path, data: data);
  }
}
```

### **3. Data Models with Dart Mappable**
Define your models using the `@MappableClass` annotation.

```dart
import 'package:dart_mappable/dart_mappable.dart';

part 'player.mapper.dart'; // generated file

@MappableClass()
class Player with PlayerMappable {
  final String id;
  final String name;
  final String? title;
  final String fed;
  final int ratingClassical;

  Player({
    required this.id,
    required this.name,
    this.title,
    required this.fed,
    required this.ratingClassical,
  });
}
```

### **4. Example: Advanced Search Query**
Here is a complete function to perform the complex "High Rated Norwegian Players" query.

```dart
Future<List<Player>> searchHighRatedPlayers() async {
  final api = GamebaseApi();
  
  // Construct the complex query object
  final queryBody = {
    "resource": "player",
    "where": {
      "and": [
        {"field": "fed", "op": "eq", "value": "NOR"},
        {"field": "ratingClassical", "op": "gt", "value": 2700}
      ]
    },
    "orderBy": [
      {"field": "ratingClassical", "direction": "desc"}
    ],
    "pageNumber": 1,
    "pageSize": 10
  };

  final response = await api.post('/search/query', data: queryBody);
  
  if (response.statusCode == 200 && response.data['status'] == 'success') {
    final List<dynamic> rawList = response.data['data'];
    // Use the generated Mapper to deserialise
    return rawList.map((json) => PlayerMapper.fromMap(json)).toList();
  }
  
  return [];
}
```

### **5. Example: Opening Explorer**
Fetching move statistics for a given board position.

```dart
Future<List<MoveAggregate>> getOpeningMoves(String fen) async {
  final api = GamebaseApi();
  
  final response = await api.get(
    '/game-position/aggregates',
    queryParameters: {
      'fen': fen,
      'minRating': 2000, // Optional: Filter for high-level games only
      'timeControl': 'CLASSICAL'
    },
  );

  if (response.statusCode == 200) {
    // Assuming you have a MoveAggregate model w/ MoveAggregateMappable
    final List<dynamic> movesJson = response.data['data']['moves'];
    return movesJson.map((m) => MoveAggregateMapper.fromMap(m)).toList();
  }
  
  return [];
}
```
