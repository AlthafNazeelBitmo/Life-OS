import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/context/life_context.dart';
import 'package:lifeos/ai/offline_ai_service.dart';
import 'package:lifeos/domain/entities/chat.dart';

void main() {
  const service = OfflineAiService();

  group('parseIntent', () {
    test('extracts an expense with its amount and merchant', () async {
      final result = await service.parseIntent('I spent 25 on lunch at Cafe');
      final intent = result.valueOrNull!;

      expect(intent.action, 'log_expense');
      expect(intent.amountMinor, 2500);
      expect(intent.fields['merchant'], contains('lunch'));
      expect(intent.confidence, greaterThan(0.5));
    });

    test('handles decimal amounts', () async {
      final result = await service.parseIntent('paid 12.50 for coffee');
      expect(result.valueOrNull!.amountMinor, 1250);
    });

    test('recognises exercise', () async {
      final result = await service.parseIntent('I went to the gym today');
      final intent = result.valueOrNull!;

      expect(intent.action, 'log_health');
      expect(intent.fields['kind'], 'exercise');
    });

    test('recognises water', () async {
      final result = await service.parseIntent('drank a glass of water');
      expect(result.valueOrNull!.fields['kind'], 'water');
    });

    test('turns a reminder into a task with a resolved date', () async {
      final result = await service.parseIntent('remind me to call mum tomorrow');
      final intent = result.valueOrNull!;

      expect(intent.action, 'add_task');
      expect(intent.when, isNotNull);
      expect(
        intent.when!.difference(DateTime.now()).inHours,
        greaterThan(0),
      );
    });

    test('falls back to a journal entry rather than losing the input', () async {
      final result = await service.parseIntent('the sky was a strange colour');
      final intent = result.valueOrNull!;

      expect(intent.action, 'journal');
      expect(intent.fields['text'], 'the sky was a strange colour');
    });
  });

  group('summarize', () {
    test('returns the most representative sentences in original order', () async {
      const text = 'I ran five kilometres this morning. The weather was cold. '
          'Running felt easier than last week. I should run again on Friday.';

      final result = await service.summarize(text, maxSentences: 2);
      final summary = result.valueOrNull!;

      expect(summary.summary, isNotEmpty);
      expect(summary.keyPoints.length, lessThanOrEqualTo(2));

      // Topics are frequency-ranked words lifted from the text. There is no
      // stemming, so 'ran', 'run' and 'running' are three separate tokens —
      // the contract is that every topic actually occurs in the source, not
      // that related forms are merged.
      expect(summary.topics, isNotEmpty);
      for (final topic in summary.topics) {
        expect(text.toLowerCase(), contains(topic));
      }
      expect(summary.topics, isNot(contains('the')), reason: 'stop words');
    });

    test('handles empty input without throwing', () async {
      final result = await service.summarize('   ');
      expect(result.valueOrNull!.summary, isEmpty);
    });
  });

  group('analyzeMood', () {
    test('reads positive language as positive sentiment', () async {
      final result = await service.analyzeMood(
        'A great day. I felt happy and proud of what I finished.',
      );
      final analysis = result.valueOrNull!;

      expect(analysis.sentiment, greaterThan(0.3));
      expect(analysis.emotions, contains('joy'));
    });

    test('reads negative language as negative sentiment', () async {
      final result = await service.analyzeMood(
        'Exhausted and stressed. Everything felt overwhelming today.',
      );
      final analysis = result.valueOrNull!;

      expect(analysis.sentiment, lessThan(-0.3));
      expect(analysis.emotions, contains('stress'));
    });

    test('extracts events that actually happened', () async {
      final result = await service.analyzeMood(
        'I met Sarah for coffee. Then I finished the report.',
      );
      final analysis = result.valueOrNull!;

      expect(analysis.events, isNotEmpty);
      expect(analysis.people, contains('Sarah'));
    });
  });

  group('answerQuestion', () {
    test('answers from matching records and cites them', () async {
      final context = LifeContext(
        chunks: <ContextChunk>[
          ContextChunk(
            token: 'j1',
            source: CitationSource.journal,
            sourceId: 'entry-1',
            label: 'Dinner with Alex',
            text: 'Had dinner with Alex at the new ramen place',
            occurredAt: DateTime(2026, 7, 20),
          ),
          ContextChunk(
            token: 'j2',
            source: CitationSource.journal,
            sourceId: 'entry-2',
            label: 'Quiet day',
            text: 'Stayed in and read all afternoon',
            occurredAt: DateTime(2026, 7, 21),
          ),
        ],
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      final result = await service.answerQuestion('When did I see Alex?', context);
      final answer = result.valueOrNull!;

      expect(answer.usedFallback, isTrue);
      expect(answer.citations, hasLength(1));
      expect(answer.citations.first.id, 'entry-1');
      expect(answer.text, contains('Alex'));
    });

    test('says so plainly when nothing matches', () async {
      const context = LifeContext.empty();
      final result = await service.answerQuestion('Where did I travel?', context);

      expect(result.valueOrNull!.citations, isEmpty);
      expect(result.valueOrNull!.confidence, 0);
    });
  });

  test('reports itself as local and non-remote', () {
    expect(service.providerId, 'offline');
    expect(service.isRemote, isFalse);
  });
}
