import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Small, synchronous key/value storage for things that are not domain records:
/// settings, cached AI answers, "last seen" markers, draft text.
///
/// Domain data lives in Drift. This exists because reads here are synchronous,
/// which lets the app paint its first frame without awaiting a database.
abstract interface class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);

  bool? getBool(String key);
  Future<void> setBool(String key, {required bool value});

  int? getInt(String key);
  Future<void> setInt(String key, int value);

  DateTime? getDateTime(String key);
  Future<void> setDateTime(String key, DateTime value);

  Map<String, dynamic>? getJson(String key);
  Future<void> setJson(String key, Map<String, dynamic> value);

  Future<void> remove(String key);
  Future<void> clear();
  bool containsKey(String key);
}

class HiveKeyValueStore implements KeyValueStore {
  HiveKeyValueStore(this._box);

  final Box<dynamic> _box;

  static const String boxName = 'lifeos_cache';

  /// Opens the backing box. Called once during bootstrap.
  static Future<HiveKeyValueStore> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<dynamic>(boxName);
    return HiveKeyValueStore(box);
  }

  @override
  bool containsKey(String key) => _box.containsKey(key);

  @override
  String? getString(String key) => _box.get(key) as String?;

  @override
  Future<void> setString(String key, String value) => _box.put(key, value);

  @override
  bool? getBool(String key) => _box.get(key) as bool?;

  @override
  Future<void> setBool(String key, {required bool value}) =>
      _box.put(key, value);

  @override
  int? getInt(String key) => _box.get(key) as int?;

  @override
  Future<void> setInt(String key, int value) => _box.put(key, value);

  @override
  DateTime? getDateTime(String key) {
    final raw = _box.get(key);
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  Future<void> setDateTime(String key, DateTime value) =>
      _box.put(key, value.toIso8601String());

  @override
  Map<String, dynamic>? getJson(String key) {
    final raw = _box.get(key) as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      // A corrupt cache entry must never take the app down; drop it instead.
      unawaited(_box.delete(key));
      return null;
    }
  }

  @override
  Future<void> setJson(String key, Map<String, dynamic> value) =>
      _box.put(key, jsonEncode(value));

  @override
  Future<void> remove(String key) => _box.delete(key);

  @override
  Future<void> clear() => _box.clear();
}

/// In-memory implementation for tests and for the first frame before Hive has
/// finished opening.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<void> setBool(String key, {required bool value}) async =>
      _values[key] = value;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  DateTime? getDateTime(String key) {
    final raw = _values[key];
    return raw is String ? DateTime.tryParse(raw) : raw as DateTime?;
  }

  @override
  Future<void> setDateTime(String key, DateTime value) async =>
      _values[key] = value.toIso8601String();

  @override
  Map<String, dynamic>? getJson(String key) {
    final raw = _values[key] as String?;
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> setJson(String key, Map<String, dynamic> value) async =>
      _values[key] = jsonEncode(value);

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}

/// Well-known cache keys, kept in one place so they cannot drift apart.
abstract final class CacheKeys {
  const CacheKeys._();

  static const String settings = 'settings';

  /// Chosen during onboarding, before there is a profile to attach them to.
  /// Read back into `LifeContext.focusAreas` so the assistant knows what the
  /// user actually came here for.
  static const String focusAreas = 'onboarding.focus_areas';
  static const String lastSession = 'auth.last_session';
  static const String dashboardSnapshot = 'dashboard.snapshot';
  static const String dailyBriefing = 'ai.daily_briefing';
  static const String eveningReflection = 'ai.evening_reflection';
  static const String journalDraft = 'journal.draft';
  static const String lastSyncCursor = 'sync.cursor';
  static const String lifeScoreHistory = 'analytics.life_score';

  static String aiAnswer(String hash) => 'ai.answer.$hash';
}
