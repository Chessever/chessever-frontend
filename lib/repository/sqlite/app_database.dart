import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton SQLite database service for the app.
/// Replaces SharedPreferences for all local storage except Supabase auth.
///
/// Benefits over SharedPreferences:
/// - SQLite uses a proper database format, not XML that can corrupt
/// - Better performance for large datasets
/// - Atomic transactions
/// - No Android-specific hanging issues
class AppDatabase {
  AppDatabase._();
  static final AppDatabase _instance = AppDatabase._();
  static AppDatabase get instance => _instance;

  Database? _database;
  Completer<Database>? _initCompleter;
  static const Duration _initTimeout = Duration(seconds: 4);
  static const String _dbFileName = 'chessever_app.db';
  String? _cachedDbPath;

  /// Table for simple key-value storage (replaces SharedPreferences)
  static const String _kvTable = 'key_value_store';

  /// Table for cached data with timestamps and user scoping
  static const String _cacheTable = 'cache_store';

  /// Table for list data (like starred items)
  static const String _listTable = 'list_store';

  /// Get the database instance, initializing if needed.
  Future<Database> get database async {
    if (_database != null) return _database!;

    // Prevent multiple simultaneous initializations
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<Database>();

    try {
      final db = await _initDatabase().timeout(
        _initTimeout,
        onTimeout: () {
          throw TimeoutException('SQLite init timed out after $_initTimeout');
        },
      );
      _database = db;
      _initCompleter!.complete(db);
      return db;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final path = await _resolveDatabasePath();

    if (kDebugMode) {
      print('SQLite database path: $path');
    }

    return openDatabase(
      path,
      version: 1,
      singleInstance: true,
      onConfigure: _configureDatabase,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<String> _resolveDatabasePath() async {
    if (_cachedDbPath != null) return _cachedDbPath!;
    try {
      final dbDirectory = await getDatabasesPath();
      _cachedDbPath = join(dbDirectory, _dbFileName);
      return _cachedDbPath!;
    } catch (_) {
      // Fallback path if platform DB directory lookup fails.
      final documentsDirectory = await getApplicationDocumentsDirectory();
      _cachedDbPath = join(documentsDirectory.path, _dbFileName);
      return _cachedDbPath!;
    }
  }

  Future<void> _configureDatabase(Database db) async {
    // Keep pragma setup best-effort so a platform-specific pragma issue does
    // not fail DB initialization on either Android or iOS.
    await _executePragmaSafe(db, 'PRAGMA foreign_keys=ON');
    try {
      // sqflite helper uses platform-safe internals for journal mode setup.
      await db.setJournalMode('WAL');
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ SQLite journal mode WAL unavailable: $e');
      }
    }
    await _executePragmaSafe(db, 'PRAGMA synchronous=NORMAL');
    await _executePragmaSafe(db, 'PRAGMA temp_store=MEMORY');
    await _executePragmaSafe(db, 'PRAGMA busy_timeout=1000');
  }

  Future<void> _executePragmaSafe(Database db, String statement) async {
    try {
      await db.execute(statement);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ SQLite pragma failed ($statement): $e');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Key-value store for simple settings
    await db.execute('''
      CREATE TABLE $_kvTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');

    // Cache store for data with timestamps and optional user scoping
    await db.execute('''
      CREATE TABLE $_cacheTable (
        key TEXT NOT NULL,
        user_id TEXT,
        value TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (key, user_id)
      )
    ''');

    // List store for arrays of items (starred, favorites, etc.)
    await db.execute('''
      CREATE TABLE $_listTable (
        key TEXT NOT NULL,
        user_id TEXT,
        items TEXT NOT NULL,
        PRIMARY KEY (key, user_id)
      )
    ''');

    // Create indexes for faster lookups
    await db.execute('CREATE INDEX idx_cache_key ON $_cacheTable (key)');
    await db.execute('CREATE INDEX idx_cache_user ON $_cacheTable (user_id)');
    await db.execute('CREATE INDEX idx_list_key ON $_listTable (key)');

    if (kDebugMode) {
      print(
        'SQLite database created with tables: $_kvTable, $_cacheTable, $_listTable',
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations here
    if (kDebugMode) {
      print('SQLite database upgrade from v$oldVersion to v$newVersion');
    }
  }

  // ============================================
  // KEY-VALUE OPERATIONS (replaces SharedPreferences simple values)
  // ============================================

  /// Set a string value
  Future<void> setString(String key, String value) async {
    final db = await database;
    await db.insert(_kvTable, {
      'key': key,
      'value': value,
      'type': 'string',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get a string value
  Future<String?> getString(String key) async {
    final db = await database;
    final result = await db.query(
      _kvTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  /// Set an integer value
  Future<void> setInt(String key, int value) async {
    final db = await database;
    await db.insert(_kvTable, {
      'key': key,
      'value': value.toString(),
      'type': 'int',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get an integer value
  Future<int?> getInt(String key) async {
    final db = await database;
    final result = await db.query(
      _kvTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return int.tryParse(result.first['value'] as String? ?? '');
  }

  /// Set a boolean value
  Future<void> setBool(String key, bool value) async {
    final db = await database;
    await db.insert(_kvTable, {
      'key': key,
      'value': value ? '1' : '0',
      'type': 'bool',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get a boolean value
  Future<bool?> getBool(String key) async {
    final db = await database;
    final result = await db.query(
      _kvTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['value'] == '1';
  }

  /// Set a JSON-encodable object
  Future<void> setJson(String key, Object value) async {
    final db = await database;
    await db.insert(_kvTable, {
      'key': key,
      'value': jsonEncode(value),
      'type': 'json',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get a JSON-decoded object
  Future<T?> getJson<T>(String key) async {
    final db = await database;
    final result = await db.query(
      _kvTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final value = result.first['value'] as String?;
    if (value == null) return null;
    return jsonDecode(value) as T?;
  }

  /// Remove a key-value pair
  Future<void> remove(String key) async {
    final db = await database;
    await db.delete(_kvTable, where: 'key = ?', whereArgs: [key]);
  }

  /// Check if a key exists
  Future<bool> containsKey(String key) async {
    final db = await database;
    final result = await db.query(
      _kvTable,
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ============================================
  // CACHE OPERATIONS (with timestamps and user scoping)
  // ============================================

  /// Set cached data with timestamp
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {
    final db = await database;
    await db.insert(_cacheTable, {
      'key': key,
      'user_id': userId ?? '',
      'value': value,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get cached data with optional staleness check
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async {
    final db = await database;
    final result = await db.query(
      _cacheTable,
      columns: ['value', 'cached_at'],
      where: 'key = ? AND user_id = ?',
      whereArgs: [key, userId ?? ''],
      limit: 1,
    );

    if (result.isEmpty) return null;

    final entry = CacheEntry(
      value: result.first['value'] as String,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
        result.first['cached_at'] as int,
      ),
    );

    // Check if cache is stale
    if (maxAge != null) {
      final age = DateTime.now().difference(entry.cachedAt);
      if (age > maxAge) return null;
    }

    return entry;
  }

  /// Remove cached data
  Future<void> removeCache({required String key, String? userId}) async {
    final db = await database;
    await db.delete(
      _cacheTable,
      where: 'key = ? AND user_id = ?',
      whereArgs: [key, userId ?? ''],
    );
  }

  /// Clear all cache for a user
  Future<void> clearUserCache(String userId) async {
    final db = await database;
    await db.delete(_cacheTable, where: 'user_id = ?', whereArgs: [userId]);
  }

  /// Clear cache entries matching a key pattern
  Future<void> clearCacheByPrefix(String prefix) async {
    final db = await database;
    await db.delete(_cacheTable, where: 'key LIKE ?', whereArgs: ['$prefix%']);
  }

  /// Fetch multiple cache entries in a single SQL query.
  /// Returns a map of key → CacheEntry for keys that exist.
  Future<Map<String, CacheEntry>> getCacheMulti({
    required List<String> keys,
    String? userId,
  }) async {
    if (keys.isEmpty) return {};
    final db = await database;
    final uid = userId ?? '';
    final placeholders = List.filled(keys.length, '?').join(', ');
    final result = await db.query(
      _cacheTable,
      columns: ['key', 'value', 'cached_at'],
      where: 'key IN ($placeholders) AND user_id = ?',
      whereArgs: [...keys, uid],
    );
    final map = <String, CacheEntry>{};
    for (final row in result) {
      map[row['key'] as String] = CacheEntry(
        value: row['value'] as String,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(row['cached_at'] as int),
      );
    }
    return map;
  }

  /// Fetch cache entries whose keys start with any of the provided prefixes.
  /// Prefixes are escaped for SQL LIKE matching.
  Future<Map<String, CacheEntry>> getCacheByPrefixes({
    required List<String> prefixes,
    String? userId,
  }) async {
    if (prefixes.isEmpty) return {};

    final db = await database;
    final uid = userId ?? '';
    final escapedPrefixes = prefixes.map(_escapeLikePattern).toList();
    final likeClauses = List.filled(
      escapedPrefixes.length,
      "key LIKE ? ESCAPE '\\'",
    ).join(' OR ');

    final result = await db.query(
      _cacheTable,
      columns: ['key', 'value', 'cached_at'],
      where: '($likeClauses) AND user_id = ?',
      whereArgs: [...escapedPrefixes.map((prefix) => '$prefix%'), uid],
    );

    final map = <String, CacheEntry>{};
    for (final row in result) {
      map[row['key'] as String] = CacheEntry(
        value: row['value'] as String,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(row['cached_at'] as int),
      );
    }
    return map;
  }

  /// Write multiple cache entries in a single transaction.
  Future<void> setCacheBatch(
    Map<String, String> entries, {
    String? userId,
  }) async {
    if (entries.isEmpty) return;
    final db = await database;
    final uid = userId ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final entry in entries.entries) {
      batch.insert(_cacheTable, {
        'key': entry.key,
        'user_id': uid,
        'value': entry.value,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  String _escapeLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  // ============================================
  // LIST OPERATIONS (for starred items, favorites, etc.)
  // ============================================

  /// Set a list of strings
  Future<void> setList({
    required String key,
    required List<String> items,
    String? userId,
  }) async {
    final db = await database;
    await db.insert(_listTable, {
      'key': key,
      'user_id': userId ?? '',
      'items': jsonEncode(items),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get a list of strings
  Future<List<String>> getList({required String key, String? userId}) async {
    final db = await database;
    final result = await db.query(
      _listTable,
      columns: ['items'],
      where: 'key = ? AND user_id = ?',
      whereArgs: [key, userId ?? ''],
      limit: 1,
    );

    if (result.isEmpty) return [];

    final items = result.first['items'] as String?;
    if (items == null) return [];

    final decoded = jsonDecode(items) as List;
    return decoded.cast<String>();
  }

  /// Add item to a list (atomic read-then-write in a single transaction)
  Future<void> addToList({
    required String key,
    required String item,
    String? userId,
  }) async {
    final db = await database;
    final uid = userId ?? '';
    await db.transaction((txn) async {
      final result = await txn.query(
        _listTable,
        where: 'key = ? AND user_id = ?',
        whereArgs: [key, uid],
      );

      List<String> items = [];
      if (result.isNotEmpty) {
        final raw = result.first['items'] as String?;
        if (raw != null) {
          items = (jsonDecode(raw) as List).cast<String>();
        }
      }

      if (!items.contains(item)) {
        items.add(item);
        await txn.insert(_listTable, {
          'key': key,
          'user_id': uid,
          'items': jsonEncode(items),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Remove item from a list (atomic read-then-write in a single transaction)
  Future<void> removeFromList({
    required String key,
    required String item,
    String? userId,
  }) async {
    final db = await database;
    final uid = userId ?? '';
    await db.transaction((txn) async {
      final result = await txn.query(
        _listTable,
        where: 'key = ? AND user_id = ?',
        whereArgs: [key, uid],
      );

      if (result.isEmpty) return;

      final raw = result.first['items'] as String?;
      if (raw == null) return;

      final items = (jsonDecode(raw) as List).cast<String>();
      if (items.remove(item)) {
        await txn.insert(_listTable, {
          'key': key,
          'user_id': uid,
          'items': jsonEncode(items),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Check if list contains item
  Future<bool> listContains({
    required String key,
    required String item,
    String? userId,
  }) async {
    final items = await getList(key: key, userId: userId);
    return items.contains(item);
  }

  /// Clear a list
  Future<void> clearList({required String key, String? userId}) async {
    final db = await database;
    await db.delete(
      _listTable,
      where: 'key = ? AND user_id = ?',
      whereArgs: [key, userId ?? ''],
    );
  }

  // ============================================
  // BATCH / TRANSACTION OPERATIONS
  // ============================================

  /// Set cache and an int key atomically in one transaction.
  /// Avoids two separate writes that compete for the SQLite lock.
  Future<void> setCacheAndInt({
    required String cacheKey,
    required String cacheValue,
    String? userId,
    required String intKey,
    required int intValue,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert(_cacheTable, {
        'key': cacheKey,
        'user_id': userId ?? '',
        'value': cacheValue,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(_kvTable, {
        'key': intKey,
        'value': intValue.toString(),
        'type': 'int',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // ============================================
  // UTILITY OPERATIONS
  // ============================================

  /// Clear all data (for logout or reset)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_kvTable);
    await db.delete(_cacheTable);
    await db.delete(_listTable);
  }

  /// Clear all data for a specific user
  Future<void> clearAllForUser(String userId) async {
    final db = await database;
    await db.delete(_cacheTable, where: 'user_id = ?', whereArgs: [userId]);
    await db.delete(_listTable, where: 'user_id = ?', whereArgs: [userId]);
  }

  /// Get all keys (for debugging)
  Future<List<String>> getAllKeys() async {
    final db = await database;
    final result = await db.query(_kvTable, columns: ['key']);
    return result.map((r) => r['key'] as String).toList();
  }

  /// Close the database
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _initCompleter = null;
    }
  }

  /// Reset the database by closing and deleting the file.
  /// Use to recover from corrupted SQLite files on Android.
  Future<void> reset() async {
    await close();
    try {
      final path = await _resolveDatabasePath();
      await deleteDatabase(path);
      if (kDebugMode) {
        print('🧹 SQLite database deleted: $path');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to delete SQLite database: $e');
      }
    }
  }
}

/// Cache entry with value and timestamp
class CacheEntry {
  final String value;
  final DateTime cachedAt;

  CacheEntry({required this.value, required this.cachedAt});

  bool isStale(Duration maxAge) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }
}

/// Riverpod provider for the database
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Async provider that ensures database is initialized
final appDatabaseReadyProvider = FutureProvider<Database>((ref) async {
  return AppDatabase.instance.database;
});
