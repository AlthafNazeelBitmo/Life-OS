import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/chat.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/recurrence.dart';

/// SQLite stores scalars; these adapters carry the few structured values that
/// are genuinely part of a single row (a tag list, a recurrence rule) without
/// inventing join tables for data that is never queried independently.

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String>[];
    return (jsonDecode(fromDb) as List<dynamic>).cast<String>();
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <int>[];
    return (jsonDecode(fromDb) as List<dynamic>).cast<int>();
  }

  @override
  String toSql(List<int> value) => jsonEncode(value);
}

class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String, dynamic>{};
    return jsonDecode(fromDb) as Map<String, dynamic>;
  }

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}

class RecurrenceConverter extends TypeConverter<Recurrence?, String?> {
  const RecurrenceConverter();

  @override
  Recurrence? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    return Recurrence.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
  }

  @override
  String? toSql(Recurrence? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

class AnalysisConverter extends TypeConverter<JournalAnalysis?, String?> {
  const AnalysisConverter();

  @override
  JournalAnalysis? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    return JournalAnalysis.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
  }

  @override
  String? toSql(JournalAnalysis? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

class GeoPointConverter extends TypeConverter<GeoPoint?, String?> {
  const GeoPointConverter();

  @override
  GeoPoint? fromSql(String? fromDb) {
    if (fromDb == null || fromDb.isEmpty) return null;
    return GeoPoint.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
  }

  @override
  String? toSql(GeoPoint? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

class CitationListConverter extends TypeConverter<List<Citation>, String> {
  const CitationListConverter();

  @override
  List<Citation> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <Citation>[];
    return (jsonDecode(fromDb) as List<dynamic>)
        .map((raw) => Citation.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  @override
  String toSql(List<Citation> value) =>
      jsonEncode(value.map((c) => c.toJson()).toList());
}

class DoubleMapConverter extends TypeConverter<Map<String, double>, String> {
  const DoubleMapConverter();

  @override
  Map<String, double> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String, double>{};
    return (jsonDecode(fromDb) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  @override
  String toSql(Map<String, double> value) => jsonEncode(value);
}
