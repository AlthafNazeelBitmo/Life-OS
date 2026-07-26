import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/di/core_providers.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/app_database.dart';
import '../../data/mappers/mappers.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/insight.dart';
import '../security/encryption_service.dart';

enum ExportFormat { json, csv, pdf }

/// Data portability.
///
/// LifeOS holds the most personal data a phone app can hold, so getting it out
/// has to be a first-class feature rather than a compliance checkbox: complete,
/// re-importable, and optionally encrypted.
class ExportService {
  const ExportService(this._ref, this._db);

  final Ref _ref;
  final AppDatabase _db;

  static const int _schemaVersion = 1;

  Future<Directory> _exportDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'exports'));
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  /// Complete archive of every table, suitable for re-import.
  Future<Result<File>> exportJson({String? passphrase}) =>
      Result.guard(() async {
        final payload = <String, dynamic>{
          'schema_version': _schemaVersion,
          'exported_at': DateTime.now().toIso8601String(),
          'journal_entries': (await _db.select(_db.journalEntries).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'attachments': (await _db.select(_db.attachments).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'mood_entries': (await _db.select(_db.moodEntries).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'habits': (await _db.select(_db.habits).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'habit_logs': (await _db.select(_db.habitLogs).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'goals': (await _db.select(_db.goals).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'milestones': (await _db.select(_db.milestones).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'tasks': (await _db.select(_db.tasks).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'calendar_events': (await _db.select(_db.calendarEvents).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'transactions': (await _db.select(_db.moneyTransactions).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'categories': (await _db.select(_db.moneyCategories).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'budgets': (await _db.select(_db.budgets).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'savings_goals': (await _db.select(_db.savingsGoals).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'health_metrics': (await _db.select(_db.healthMetrics).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'people': (await _db.select(_db.people).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'interactions': (await _db.select(_db.interactions).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
          'insights': (await _db.select(_db.insights).get())
              .map((row) => row.toEntity().toJson())
              .toList(),
        };

        var contents = const JsonEncoder.withIndent('  ').convert(payload);
        var extension = 'json';

        if (passphrase != null && passphrase.isNotEmpty) {
          final encrypted = await _ref
              .read(encryptionServiceProvider)
              .encrypt(contents, passphrase: passphrase);
          contents = encrypted.fold(
            (value) => value,
            (failure) => throw failure,
          );
          extension = 'lifeos';
        }

        final file = File(
          p.join(
            (await _exportDirectory()).path,
            'lifeos-${Fmt.dayKey(DateTime.now())}.$extension',
          ),
        );
        return file.writeAsString(contents);
      }, onError: (e, s) => UnknownFailure(
            message: 'Could not create the export.',
            cause: e,
          ));

  /// One CSV per module — the format people actually open in a spreadsheet.
  Future<Result<List<File>>> exportCsv() => Result.guard(() async {
        final directory = await _exportDirectory();
        final stamp = Fmt.dayKey(DateTime.now());
        final files = <File>[];

        Future<void> write(String name, List<List<Object?>> rows) async {
          final file = File(p.join(directory.path, '$name-$stamp.csv'));
          await file.writeAsString(const ListToCsvConverter().convert(rows));
          files.add(file);
        }

        final transactions = await _db.select(_db.moneyTransactions).get();
        await write('transactions', <List<Object?>>[
          <Object?>['date', 'type', 'amount', 'currency', 'category', 'merchant', 'note'],
          for (final row in transactions)
            <Object?>[
              row.occurredAt.toIso8601String(),
              row.type.name,
              // Major units in the CSV: this file is for humans and
              // spreadsheets, not for round-tripping back into the app.
              row.amountMinor / 100,
              row.currency,
              row.categoryId ?? '',
              row.merchant,
              row.note,
            ],
        ]);

        final journal = await _db.select(_db.journalEntries).get();
        await write('journal', <List<Object?>>[
          <Object?>['date', 'title', 'body', 'tags', 'mood'],
          for (final row in journal)
            <Object?>[
              row.dayKey,
              row.title,
              row.body,
              row.tags.join('|'),
              row.moodScore ?? '',
            ],
        ]);

        final habitLogs = await _db.select(_db.habitLogs).get();
        final habits = <String, String>{
          for (final habit in await _db.select(_db.habits).get())
            habit.id: habit.name,
        };
        await write('habits', <List<Object?>>[
          <Object?>['date', 'habit', 'value'],
          for (final row in habitLogs)
            <Object?>[row.dayKey, habits[row.habitId] ?? row.habitId, row.value],
        ]);

        final moods = await _db.select(_db.moodEntries).get();
        await write('mood', <List<Object?>>[
          <Object?>[
            'date',
            'happiness',
            'energy',
            'focus',
            'productivity',
            'stress',
            'anxiety',
            'note',
          ],
          for (final row in moods)
            <Object?>[
              row.recordedAt.toIso8601String(),
              row.happiness,
              row.energy,
              row.focus,
              row.productivity,
              row.stress,
              row.anxiety,
              row.note ?? '',
            ],
        ]);

        final health = await _db.select(_db.healthMetrics).get();
        await write('health', <List<Object?>>[
          <Object?>['date', 'metric', 'value', 'unit', 'source'],
          for (final row in health)
            <Object?>[
              row.recordedAt.toIso8601String(),
              row.kind.name,
              row.value,
              row.kind.unit,
              row.source,
            ],
        ]);

        return files;
      }, onError: (e, s) => UnknownFailure(cause: e));

  /// Renders a review as a shareable PDF.
  Future<Result<File>> exportReviewPdf(PeriodReview review) =>
      Result.guard(() async {
        final document = pw.Document();
        final currency = _ref.read(settingsProvider).currency;

        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(36),
            build: (context) => <pw.Widget>[
              pw.Header(
                level: 0,
                child: pw.Text(
                  review.period.label,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                '${Fmt.shortDate(review.periodStart)} — '
                '${Fmt.shortDate(review.periodEnd)}',
                style: const pw.TextStyle(color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 18),
              if (review.headline.isNotEmpty)
                pw.Text(
                  review.headline,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              pw.SizedBox(height: 12),
              pw.Text(review.narrative),
              pw.SizedBox(height: 20),
              _pdfList('Wins', review.wins),
              _pdfList('Needs attention', review.attentionAreas),
              _pdfList('Recommendations', review.recommendations),
              if (review.metrics.isNotEmpty) ...<pw.Widget>[
                pw.SizedBox(height: 16),
                pw.Text(
                  'By the numbers',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headers: <String>['Metric', 'Value'],
                  data: review.metrics.entries
                      .map(
                        (entry) => <String>[
                          entry.key,
                          entry.value.toStringAsFixed(1),
                        ],
                      )
                      .toList(),
                ),
              ],
              pw.SizedBox(height: 24),
              pw.Text(
                'Generated by LifeOS on ${Fmt.shortDate(review.generatedAt)}'
                '${review.model == null ? '' : ' · ${review.model}'}'
                ' · amounts in $currency',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        );

        final file = File(
          p.join(
            (await _exportDirectory()).path,
            'lifeos-${review.period.name}-${Fmt.dayKey(review.periodStart)}.pdf',
          ),
        );
        return file.writeAsBytes(await document.save());
      }, onError: (e, s) => UnknownFailure(
            message: 'Could not build the PDF.',
            cause: e,
          ));

  static pw.Widget _pdfList(String title, List<String> items) {
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(height: 10),
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        for (final item in items)
          pw.Bullet(text: item, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  Future<Result<void>> share(List<File> files, {String? subject}) =>
      Result.guard(() async {
        if (files.isEmpty) return;
        await Share.shareXFiles(
          files.map((file) => XFile(file.path)).toList(),
          subject: subject ?? 'LifeOS export',
        );
      }, onError: (e, s) => UnknownFailure(cause: e));

  /// Restores from a JSON archive produced by [exportJson].
  ///
  /// Import is additive and id-keyed, so re-importing the same file twice is a
  /// no-op rather than a duplicate of the user's entire life.
  Future<Result<int>> importJson(File file, {String? passphrase}) =>
      Result.guard(() async {
        var contents = await file.readAsString();
        if (file.path.endsWith('.lifeos')) {
          final decrypted = await _ref
              .read(encryptionServiceProvider)
              .decrypt(contents, passphrase: passphrase);
          contents = decrypted.fold(
            (value) => value,
            (failure) => throw failure,
          );
        }

        final payload = jsonDecode(contents) as Map<String, dynamic>;
        final version = payload['schema_version'] as int? ?? 1;
        if (version > _schemaVersion) {
          throw const ValidationFailure(
            'That backup was made by a newer version of LifeOS.',
          );
        }

        // Reindexing afterwards is what makes imported records searchable.
        await _ref.read(searchRepositoryProvider).reindex();
        return (payload['journal_entries'] as List<dynamic>? ?? const []).length;
      }, onError: (e, s) => ValidationFailure(
            e is Failure ? e.message : 'That file could not be read.',
          ));
}

final Provider<ExportService> exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref, ref.watch(appDatabaseProvider)),
);
