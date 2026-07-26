import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../../domain/entities/chat.dart';

/// One retrievable fact from the user's own data.
///
/// The [token] is what the model is told to cite (`[j3]`). Keeping it short
/// matters: it costs almost nothing in the prompt and it gives the app an exact
/// key to resolve back to a real record.
@immutable
class ContextChunk {
  const ContextChunk({
    required this.token,
    required this.source,
    required this.sourceId,
    required this.label,
    required this.text,
    this.occurredAt,
  });

  final String token;
  final CitationSource source;
  final String sourceId;
  final String label;
  final String text;
  final DateTime? occurredAt;

  Citation toCitation() => Citation(
        id: sourceId,
        source: source,
        label: label,
        occurredAt: occurredAt,
        excerpt: text.length > 300 ? '${text.substring(0, 297)}…' : text,
      );

  String render() {
    final when = occurredAt == null ? '' : '${Fmt.shortDate(occurredAt!)} ';
    return '[$token] $when${source.name}: $text';
  }
}

/// Everything handed to the model for one request.
///
/// This is the grounding set. The system prompt tells the model it may only
/// assert things present here, and every claim must carry a token — which is
/// what makes "never hallucinate, always cite" enforceable rather than
/// aspirational: an answer whose tokens do not resolve gets flagged.
@immutable
class LifeContext {
  const LifeContext({
    required this.chunks,
    required this.from,
    required this.to,
    this.stats = const <String, Object?>{},
    this.userName = '',
    this.focusAreas = const <String>[],
  });

  const LifeContext.empty()
      : chunks = const <ContextChunk>[],
        from = null,
        to = null,
        stats = const <String, Object?>{},
        userName = '',
        focusAreas = const <String>[];

  final List<ContextChunk> chunks;
  final DateTime? from;
  final DateTime? to;

  /// Pre-computed aggregates (streaks, totals, averages). These are facts the
  /// model should never have to derive by counting, because it is bad at it.
  final Map<String, Object?> stats;
  final String userName;
  final List<String> focusAreas;

  bool get isEmpty => chunks.isEmpty && stats.isEmpty;

  ContextChunk? chunkFor(String token) {
    for (final chunk in chunks) {
      if (chunk.token == token) return chunk;
    }
    return null;
  }

  /// Renders the grounding block that goes into the prompt.
  String render({int maxChars = 12000}) {
    final buffer = StringBuffer();
    if (from != null && to != null) {
      buffer.writeln(
        'Window: ${Fmt.shortDate(from!)} to ${Fmt.shortDate(to!)}',
      );
    }
    if (stats.isNotEmpty) {
      buffer.writeln('\nAggregates (already computed, trust these):');
      stats.forEach((key, value) => buffer.writeln('- $key: $value'));
    }
    if (chunks.isNotEmpty) {
      buffer.writeln('\nRecords:');
      for (final chunk in chunks) {
        final line = chunk.render();
        // Truncating mid-record is better than dropping the tail of the list,
        // which would silently bias every answer towards older entries.
        if (buffer.length + line.length > maxChars) {
          buffer.writeln('… (${chunks.length} records total, list truncated)');
          break;
        }
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  /// Resolves the tokens a model cited back to real records, dropping any it
  /// invented.
  List<Citation> resolve(Iterable<String> tokens) {
    final seen = <String>{};
    final citations = <Citation>[];
    for (final token in tokens) {
      final normalised = token.replaceAll(RegExp(r'[\[\]\s]'), '');
      if (!seen.add(normalised)) continue;
      final chunk = chunkFor(normalised);
      if (chunk != null) citations.add(chunk.toCitation());
    }
    return citations;
  }
}
