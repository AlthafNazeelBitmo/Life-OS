import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../ai/ai_providers.dart';
import '../../ai/models/ai_results.dart';
import '../../core/error/failures.dart';
import '../../core/error/result.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/entities/finance.dart';
import '../../domain/entities/goal.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/task.dart';

enum VoiceStatus { idle, listening, processing, done, error }

class VoiceState {
  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.confidence = 0,
    this.result,
    this.message,
  });

  final VoiceStatus status;
  final String transcript;
  final double confidence;

  /// Human-readable description of what was saved, e.g. "Logged $25 at Cafe".
  final String? result;
  final String? message;

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    double? confidence,
    String? result,
    String? message,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        confidence: confidence ?? this.confidence,
        result: result ?? this.result,
        message: message,
      );
}

/// Speech in, structured records out.
///
/// The pipeline is: platform speech-to-text → [AIService.parseIntent] →
/// repository write. The middle step falls back to on-device regex parsing when
/// no model is configured, which is why "I spent 25 on lunch" works offline.
class VoiceInputService extends Notifier<VoiceState> {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  @override
  VoiceState build() => const VoiceState();

  Future<bool> ensureReady() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (error) => state = state.copyWith(
          status: VoiceStatus.error,
          message: error.errorMsg,
        ),
        onStatus: (status) {
          if (status == 'done' && state.status == VoiceStatus.listening) {
            unawaited(_finish());
          }
        },
      );
      return _available;
    } catch (error) {
      AppLogger.warn('voice', 'Speech init failed', error);
      return false;
    }
  }

  Future<void> startListening() async {
    if (!await ensureReady()) {
      state = const VoiceState(
        status: VoiceStatus.error,
        message: 'Speech recognition is not available on this device.',
      );
      return;
    }

    state = const VoiceState(status: VoiceStatus.listening);
    await _speech.listen(
      onResult: (result) => state = state.copyWith(
        transcript: result.recognizedWords,
        confidence: result.confidence,
      ),
      listenOptions: SpeechListenOptions(
        // Partial results drive the live caption under the mic button.
        partialResults: true,
        cancelOnError: true,
      ),
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 30),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    await _finish();
  }

  Future<void> cancel() async {
    await _speech.cancel();
    state = const VoiceState();
  }

  Future<void> _finish() async {
    final transcript = state.transcript.trim();
    if (transcript.isEmpty) {
      state = const VoiceState();
      return;
    }
    state = state.copyWith(status: VoiceStatus.processing);

    final parsed = await ref.read(aiServiceProvider).parseIntent(transcript);
    await parsed.fold(
      (intent) async {
        final applied = await apply(intent);
        state = applied.fold(
          (description) => state.copyWith(
            status: VoiceStatus.done,
            result: description,
          ),
          (failure) => state.copyWith(
            status: VoiceStatus.error,
            message: failure.message,
          ),
        );
      },
      (failure) async => state = state.copyWith(
        status: VoiceStatus.error,
        message: failure.message,
      ),
    );
  }

  /// Writes the parsed intent to the right repository.
  ///
  /// Returns a sentence describing what happened, which the UI shows for
  /// confirmation — voice capture is only trustworthy if the user can see what
  /// was understood.
  Future<Result<String>> apply(ParsedIntent intent) async {
    final now = DateTime.now();

    switch (intent.action) {
      case 'log_expense':
      case 'log_income':
        final amount = intent.amountMinor;
        if (amount == null || amount <= 0) {
          return const Err<String>(
            ValidationFailure('I did not catch an amount.'),
          );
        }
        final merchant = (intent.fields['merchant'] ?? '') as String;
        final isIncome = intent.action == 'log_income';
        final result =
            await ref.read(financeRepositoryProvider).upsert(
                  MoneyTransaction(
                    id: newId(),
                    occurredAt: intent.when ?? now,
                    amountMinor: amount,
                    type: isIncome
                        ? TransactionType.income
                        : TransactionType.expense,
                    createdAt: now,
                    merchant: merchant,
                    note: intent.transcript,
                  ),
                );
        return result.map(
          (txn) => '${isIncome ? 'Recorded' : 'Logged'} '
              '${Fmt.money(amount)}${merchant.isEmpty ? '' : ' at $merchant'}',
        );

      case 'log_habit':
        final name = ((intent.fields['habit'] ?? '') as String).toLowerCase();
        final habits =
            await ref.read(habitRepositoryProvider).watchHabits().first;
        final match = habits.where(
          (habit) => habit.name.toLowerCase().contains(name),
        );
        if (name.isEmpty || match.isEmpty) {
          return const Err<String>(
            ValidationFailure('I could not find a habit by that name.'),
          );
        }
        final habit = match.first;
        final result =
            await ref.read(habitRepositoryProvider).log(habit.id, now);
        return result.map((_) => 'Marked ${habit.name} done');

      case 'log_health':
        final kind = HealthKind.values.firstWhere(
          (value) => value.name == intent.fields['kind'],
          orElse: () => HealthKind.exercise,
        );
        final value = (intent.fields['value'] as num?)?.toDouble() ?? 1;
        final result =
            await ref.read(healthRepositoryProvider).increment(kind, value);
        return result.map(
          (_) => 'Logged ${value.toStringAsFixed(0)} ${kind.unit} '
              'of ${kind.label.toLowerCase()}',
        );

      case 'add_task':
        final text = (intent.fields['text'] ?? intent.transcript) as String;
        final result = await ref.read(taskRepositoryProvider).upsert(
              Task(
                id: newId(),
                title: _clean(text),
                createdAt: now,
                dueAt: intent.when,
                status: TaskStatus.today,
                priority: switch (intent.fields['priority']) {
                  'high' => TaskPriority.high,
                  'low' => TaskPriority.low,
                  _ => TaskPriority.medium,
                },
              ),
            );
        return result.map((task) => 'Added task "${task.title}"');

      case 'create_goal':
        final text = (intent.fields['text'] ?? intent.transcript) as String;
        final result = await ref.read(goalRepositoryProvider).upsert(
              Goal(
                id: newId(),
                title: _clean(text),
                createdAt: now,
                targetDate: intent.when,
              ),
            );
        return result.map((goal) => 'Created goal "${goal.title}"');

      case 'journal':
      default:
        final text = (intent.fields['text'] ?? intent.transcript) as String;
        final result = await ref.read(journalRepositoryProvider).upsert(
              JournalEntry(
                id: newId(),
                createdAt: now,
                updatedAt: now,
                dayKey: Fmt.dayKey(now),
                body: text,
              ),
            );
        return result.map((_) => 'Saved to your journal');
    }
  }

  /// Strips the command wrapper so "remind me to call mum" becomes "call mum".
  String _clean(String text) => text
      .replaceAll(
        RegExp(
          r'^(remind me to|remind me|i need to|todo:?|task:?|my goal is to|i want to)\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

final NotifierProvider<VoiceInputService, VoiceState> voiceInputProvider =
    NotifierProvider<VoiceInputService, VoiceState>(VoiceInputService.new);
