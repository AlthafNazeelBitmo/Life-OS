import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';

/// What a scan produced.
class ScannedReceipt {
  const ScannedReceipt({
    required this.rawText,
    this.merchant,
    this.totalMinor,
    this.date,
    this.confidence = 0,
  });

  final String rawText;
  final String? merchant;
  final int? totalMinor;
  final DateTime? date;
  final double confidence;

  bool get isUsable => totalMinor != null;
}

/// Receipt OCR.
///
/// Kept behind an interface with a working stub because ML Kit adds ~30MB to an
/// Android build and pulls in platform setup that not every deployment wants.
/// The pipeline that *interprets* the text — [ReceiptParser] — is real and unit
/// tested either way, so enabling OCR later is a dependency change, not a
/// rewrite. See docs/DEPLOYMENT.md.
abstract interface class ReceiptScanner {
  bool get isAvailable;

  Future<Result<ScannedReceipt>> scan(File image);
}

/// Default implementation: no on-device text recognition compiled in.
class StubReceiptScanner implements ReceiptScanner {
  const StubReceiptScanner();

  @override
  bool get isAvailable => false;

  @override
  Future<Result<ScannedReceipt>> scan(File image) async => const Err(
        PermissionFailure(
          'Receipt scanning is not enabled in this build. '
          'You can still attach the photo and type the amount.',
          permission: 'ocr',
        ),
      );
}

/// Turns raw OCR text into a transaction.
///
/// Pure and dependency-free so it can be tested against real receipt dumps
/// without a camera or a platform channel.
abstract final class ReceiptParser {
  const ReceiptParser._();

  static ScannedReceipt parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return ScannedReceipt(
      rawText: rawText,
      // The merchant name is almost always the first non-numeric line.
      merchant: lines
          .where((line) => !RegExp(r'^[\d\s.,\-/]+$').hasMatch(line))
          .map((line) => line.length > 40 ? line.substring(0, 40) : line)
          .firstOrNull,
      totalMinor: _findTotal(lines),
      date: _findDate(rawText),
      confidence: _findTotal(lines) == null ? 0.2 : 0.75,
    );
  }

  /// Prefers an amount on a line that says "total"; falls back to the largest
  /// number on the receipt, which is the total far more often than not.
  static int? _findTotal(List<String> lines) {
    final amountPattern = RegExp(r'(\d+[.,]\d{2})');

    for (final line in lines.reversed) {
      if (!RegExp(r'\b(total|amount due|balance)\b', caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      final match = amountPattern.firstMatch(line);
      if (match != null) return _toMinor(match.group(1)!);
    }

    final all = <int>[
      for (final line in lines)
        for (final match in amountPattern.allMatches(line))
          _toMinor(match.group(1)!),
    ];
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a > b ? a : b);
  }

  static int _toMinor(String raw) =>
      (double.parse(raw.replaceAll(',', '.')) * 100).round();

  static DateTime? _findDate(String text) {
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (iso != null) return DateTime.tryParse(iso.group(0)!);

    final slash = RegExp(r'(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})').firstMatch(text);
    if (slash == null) return null;

    // Ambiguous without a locale, so day-first is assumed and the value is only
    // ever offered as a pre-fill the user can correct.
    final day = int.parse(slash.group(1)!);
    final month = int.parse(slash.group(2)!);
    var year = int.parse(slash.group(3)!);
    if (year < 100) year += 2000;
    if (month > 12) return null;
    return DateTime(year, month, day);
  }
}

final Provider<ReceiptScanner> receiptScannerProvider = Provider<ReceiptScanner>(
  (ref) {
    // When ML Kit is compiled in, swap this for the real implementation:
    //   return MlKitReceiptScanner();
    // The rest of the app is written against the interface and needs no change.
    if (Env.enableOcr) return const StubReceiptScanner();
    return const StubReceiptScanner();
  },
);
