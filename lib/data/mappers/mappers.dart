import 'package:drift/drift.dart';

import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/finance.dart';
import '../../domain/entities/goal.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/insight.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/mood_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/task.dart';
import '../local/app_database.dart';

/// Row ↔ entity translation.
///
/// Keeping this in one file means the storage shape can change (a column split,
/// a denormalisation) without any feature code noticing — the compiler points
/// at exactly the two functions that need updating.

extension JournalRowX on JournalEntryRow {
  JournalEntry toEntity({List<Attachment> attachments = const <Attachment>[]}) =>
      JournalEntry(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        dayKey: dayKey,
        title: title,
        body: body,
        tags: tags,
        peopleIds: peopleIds,
        attachments: attachments,
        location: location,
        weather: weather,
        moodScore: moodScore,
        analysis: analysis,
        isFavorite: isFavorite,
        deletedAt: deletedAt,
      );
}

extension JournalEntryX on JournalEntry {
  JournalEntriesCompanion toCompanion() => JournalEntriesCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        dayKey: dayKey,
        title: Value(title),
        body: Value(body),
        tags: Value(tags),
        peopleIds: Value(peopleIds),
        location: Value(location),
        weather: Value(weather),
        moodScore: Value(moodScore),
        analysis: Value(analysis),
        isFavorite: Value(isFavorite),
        deletedAt: Value(deletedAt),
      );
}

extension AttachmentRowX on AttachmentRow {
  Attachment toEntity() => Attachment(
        id: id,
        entryId: entryId,
        kind: kind,
        localPath: localPath,
        createdAt: createdAt,
        remoteUrl: remoteUrl,
        caption: caption,
        transcript: transcript,
        durationMs: durationMs,
      );
}

extension AttachmentX on Attachment {
  AttachmentsCompanion toCompanion() => AttachmentsCompanion.insert(
        id: id,
        entryId: entryId,
        kind: kind,
        localPath: localPath,
        createdAt: createdAt,
        remoteUrl: Value(remoteUrl),
        caption: Value(caption),
        transcript: Value(transcript),
        durationMs: Value(durationMs),
      );
}

extension MoodRowX on MoodEntryRow {
  MoodEntry toEntity() => MoodEntry(
        id: id,
        recordedAt: recordedAt,
        dayKey: dayKey,
        happiness: happiness,
        energy: energy,
        focus: focus,
        productivity: productivity,
        stress: stress,
        anxiety: anxiety,
        note: note,
        tags: tags,
        journalEntryId: journalEntryId,
      );
}

extension MoodEntryX on MoodEntry {
  MoodEntriesCompanion toCompanion() => MoodEntriesCompanion.insert(
        id: id,
        recordedAt: recordedAt,
        dayKey: dayKey,
        happiness: Value(happiness),
        energy: Value(energy),
        focus: Value(focus),
        productivity: Value(productivity),
        stress: Value(stress),
        anxiety: Value(anxiety),
        note: Value(note),
        tags: Value(tags),
        journalEntryId: Value(journalEntryId),
      );
}

extension HabitRowX on HabitRow {
  Habit toEntity() => Habit(
        id: id,
        name: name,
        createdAt: createdAt,
        emoji: emoji,
        colorValue: colorValue,
        cadence: cadence,
        kind: kind,
        target: target,
        unit: unit,
        customSchedule: customSchedule,
        reminderMinutes: reminderMinutes,
        notes: notes,
        goalId: goalId,
        archivedAt: archivedAt,
      );
}

extension HabitX on Habit {
  HabitsCompanion toCompanion() => HabitsCompanion.insert(
        id: id,
        name: name,
        createdAt: createdAt,
        cadence: cadence,
        kind: kind,
        emoji: Value(emoji),
        colorValue: Value(colorValue),
        target: Value(target),
        unit: Value(unit),
        customSchedule: Value(customSchedule),
        reminderMinutes: Value(reminderMinutes),
        notes: Value(notes),
        goalId: Value(goalId),
        archivedAt: Value(archivedAt),
      );
}

extension HabitLogRowX on HabitLogRow {
  HabitLog toEntity() => HabitLog(
        id: id,
        habitId: habitId,
        dayKey: dayKey,
        recordedAt: recordedAt,
        value: value,
        note: note,
      );
}

extension GoalRowX on GoalRow {
  Goal toEntity({List<Milestone> milestones = const <Milestone>[]}) => Goal(
        id: id,
        title: title,
        createdAt: createdAt,
        description: description,
        horizon: horizon,
        status: status,
        category: category,
        colorValue: colorValue,
        targetDate: targetDate,
        manualProgress: manualProgress,
        milestones: milestones,
        habitIds: habitIds,
        achievedAt: achievedAt,
      );
}

extension GoalX on Goal {
  GoalsCompanion toCompanion() => GoalsCompanion.insert(
        id: id,
        title: title,
        createdAt: createdAt,
        horizon: horizon,
        status: status,
        description: Value(description),
        category: Value(category),
        colorValue: Value(colorValue),
        targetDate: Value(targetDate),
        manualProgress: Value(manualProgress),
        habitIds: Value(habitIds),
        achievedAt: Value(achievedAt),
      );
}

extension MilestoneRowX on MilestoneRow {
  Milestone toEntity() => Milestone(
        id: id,
        goalId: goalId,
        title: title,
        position: position,
        dueDate: dueDate,
        completedAt: completedAt,
        notes: notes,
      );
}

extension MilestoneX on Milestone {
  MilestonesCompanion toCompanion() => MilestonesCompanion.insert(
        id: id,
        goalId: goalId,
        title: title,
        position: Value(position),
        notes: Value(notes),
        dueDate: Value(dueDate),
        completedAt: Value(completedAt),
      );
}

extension TaskRowX on TaskRow {
  Task toEntity() => Task(
        id: id,
        title: title,
        createdAt: createdAt,
        notes: notes,
        parentId: parentId,
        priority: priority,
        status: status,
        dueAt: dueAt,
        remindAt: remindAt,
        labels: labels,
        recurrence: recurrence,
        orderIndex: orderIndex,
        goalId: goalId,
        calendarEventId: calendarEventId,
        estimateMinutes: estimateMinutes,
        completedAt: completedAt,
        aiReason: aiReason,
      );
}

extension TaskX on Task {
  TasksCompanion toCompanion() => TasksCompanion.insert(
        id: id,
        title: title,
        createdAt: createdAt,
        priority: priority,
        status: status,
        notes: Value(notes),
        parentId: Value(parentId),
        dueAt: Value(dueAt),
        remindAt: Value(remindAt),
        labels: Value(labels),
        recurrence: Value(recurrence),
        orderIndex: Value(orderIndex),
        goalId: Value(goalId),
        calendarEventId: Value(calendarEventId),
        estimateMinutes: Value(estimateMinutes),
        aiReason: Value(aiReason),
        completedAt: Value(completedAt),
      );
}

extension EventRowX on CalendarEventRow {
  CalendarEvent toEntity() => CalendarEvent(
        id: id,
        title: title,
        start: startsAt,
        end: endsAt,
        createdAt: createdAt,
        description: description,
        allDay: allDay,
        kind: kind,
        location: location,
        recurrence: recurrence,
        reminderOffsets: reminderOffsets,
        colorValue: colorValue,
        peopleIds: peopleIds,
        taskId: taskId,
        isAiScheduled: isAiScheduled,
        deletedAt: deletedAt,
      );
}

extension CalendarEventX on CalendarEvent {
  CalendarEventsCompanion toCompanion() => CalendarEventsCompanion.insert(
        id: id,
        title: title,
        startsAt: start,
        endsAt: end,
        createdAt: createdAt,
        kind: kind,
        description: Value(description),
        allDay: Value(allDay),
        location: Value(location),
        recurrence: Value(recurrence),
        reminderOffsets: Value(reminderOffsets),
        colorValue: Value(colorValue),
        peopleIds: Value(peopleIds),
        taskId: Value(taskId),
        isAiScheduled: Value(isAiScheduled),
        deletedAt: Value(deletedAt),
      );
}

extension TransactionRowX on TransactionRow {
  MoneyTransaction toEntity() => MoneyTransaction(
        id: id,
        occurredAt: occurredAt,
        amountMinor: amountMinor,
        type: type,
        createdAt: createdAt,
        currency: currency,
        categoryId: categoryId,
        merchant: merchant,
        note: note,
        tags: tags,
        recurrence: recurrence,
        receiptPath: receiptPath,
        receiptText: receiptText,
        savingsGoalId: savingsGoalId,
        deletedAt: deletedAt,
      );
}

extension MoneyTransactionX on MoneyTransaction {
  MoneyTransactionsCompanion toCompanion() => MoneyTransactionsCompanion.insert(
        id: id,
        occurredAt: occurredAt,
        amountMinor: amountMinor,
        type: type,
        createdAt: createdAt,
        currency: Value(currency),
        categoryId: Value(categoryId),
        merchant: Value(merchant),
        note: Value(note),
        tags: Value(tags),
        recurrence: Value(recurrence),
        receiptPath: Value(receiptPath),
        receiptText: Value(receiptText),
        savingsGoalId: Value(savingsGoalId),
        deletedAt: Value(deletedAt),
      );
}

extension CategoryRowX on MoneyCategoryRow {
  MoneyCategory toEntity() => MoneyCategory(
        id: id,
        name: name,
        emoji: emoji,
        colorValue: colorValue,
        kind: kind,
        isSystem: isSystem,
      );
}

extension MoneyCategoryX on MoneyCategory {
  MoneyCategoriesCompanion toCompanion() => MoneyCategoriesCompanion.insert(
        id: id,
        name: name,
        kind: kind,
        emoji: Value(emoji),
        colorValue: Value(colorValue),
        isSystem: Value(isSystem),
      );
}

extension BudgetRowX on BudgetRow {
  Budget toEntity() => Budget(
        id: id,
        limitMinor: limitMinor,
        createdAt: createdAt,
        categoryId: categoryId,
        currency: currency,
        monthKey: monthKey,
        rollsOver: rollsOver,
      );
}

extension BudgetX on Budget {
  BudgetsCompanion toCompanion() => BudgetsCompanion.insert(
        id: id,
        limitMinor: limitMinor,
        createdAt: createdAt,
        categoryId: Value(categoryId),
        currency: Value(currency),
        monthKey: Value(monthKey),
        rollsOver: Value(rollsOver),
      );
}

extension SavingsGoalRowX on SavingsGoalRow {
  SavingsGoal toEntity() => SavingsGoal(
        id: id,
        name: name,
        targetMinor: targetMinor,
        createdAt: createdAt,
        savedMinor: savedMinor,
        currency: currency,
        emoji: emoji,
        dueDate: dueDate,
        achievedAt: achievedAt,
      );
}

extension SavingsGoalX on SavingsGoal {
  SavingsGoalsCompanion toCompanion() => SavingsGoalsCompanion.insert(
        id: id,
        name: name,
        targetMinor: targetMinor,
        createdAt: createdAt,
        savedMinor: Value(savedMinor),
        currency: Value(currency),
        emoji: Value(emoji),
        dueDate: Value(dueDate),
        achievedAt: Value(achievedAt),
      );
}

extension HealthRowX on HealthMetricRow {
  HealthMetric toEntity() => HealthMetric(
        id: id,
        kind: kind,
        value: value,
        recordedAt: recordedAt,
        dayKey: dayKey,
        note: note,
        source: source,
      );
}

extension HealthMetricX on HealthMetric {
  HealthMetricsCompanion toCompanion() => HealthMetricsCompanion.insert(
        id: id,
        kind: kind,
        value: value,
        recordedAt: recordedAt,
        dayKey: dayKey,
        note: Value(note),
        source: Value(source),
      );
}

extension PersonRowX on PersonRow {
  Person toEntity() => Person(
        id: id,
        name: name,
        createdAt: createdAt,
        relation: relation,
        notes: notes,
        details: details,
        birthday: birthday,
        avatarPath: avatarPath,
        followUpEveryDays: followUpEveryDays,
        lastInteractionAt: lastInteractionAt,
        isFavorite: isFavorite,
      );
}

extension PersonX on Person {
  PeopleCompanion toCompanion() => PeopleCompanion.insert(
        id: id,
        name: name,
        createdAt: createdAt,
        relation: Value(relation),
        notes: Value(notes),
        details: Value(details),
        birthday: Value(birthday),
        avatarPath: Value(avatarPath),
        followUpEveryDays: Value(followUpEveryDays),
        lastInteractionAt: Value(lastInteractionAt),
        isFavorite: Value(isFavorite),
      );
}

extension InteractionRowX on InteractionRow {
  Interaction toEntity() => Interaction(
        id: id,
        personId: personId,
        occurredAt: occurredAt,
        channel: channel,
        summary: summary,
        journalEntryId: journalEntryId,
        eventId: eventId,
      );
}

extension InteractionX on Interaction {
  InteractionsCompanion toCompanion() => InteractionsCompanion.insert(
        id: id,
        personId: personId,
        occurredAt: occurredAt,
        channel: channel,
        summary: Value(summary),
        journalEntryId: Value(journalEntryId),
        eventId: Value(eventId),
      );
}

extension ChatThreadRowX on ChatThreadRow {
  ChatThread toEntity() => ChatThread(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        title: title,
        pinned: pinned,
      );
}

extension ChatMessageRowX on ChatMessageRow {
  ChatMessage toEntity() => ChatMessage(
        id: id,
        threadId: threadId,
        role: role,
        content: content,
        createdAt: createdAt,
        citations: citations,
        model: model,
        error: error,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
}

extension ChatMessageX on ChatMessage {
  ChatMessagesCompanion toCompanion() => ChatMessagesCompanion.insert(
        id: id,
        threadId: threadId,
        role: role,
        content: content,
        createdAt: createdAt,
        citations: Value(citations),
        model: Value(model),
        error: Value(error),
        promptTokens: Value(promptTokens),
        completionTokens: Value(completionTokens),
      );
}

extension InsightRowX on InsightRow {
  Insight toEntity() => Insight(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        citations: citations,
        confidence: confidence,
        periodStart: periodStart,
        periodEnd: periodEnd,
        data: data,
        pinned: pinned,
        dismissed: dismissed,
        model: model,
      );
}

extension InsightX on Insight {
  InsightsCompanion toCompanion() => InsightsCompanion.insert(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        citations: Value(citations),
        confidence: Value(confidence),
        periodStart: Value(periodStart),
        periodEnd: Value(periodEnd),
        data: Value(data),
        pinned: Value(pinned),
        dismissed: Value(dismissed),
        model: Value(model),
      );
}

extension ReviewRowX on ReviewRow {
  PeriodReview toEntity({List<Insight> insights = const <Insight>[]}) =>
      PeriodReview(
        id: id,
        period: period,
        periodStart: periodStart,
        periodEnd: periodEnd,
        generatedAt: generatedAt,
        headline: headline,
        narrative: narrative,
        wins: wins,
        attentionAreas: attentionAreas,
        recommendations: recommendations,
        insights: insights,
        metrics: metrics,
        citations: citations,
        model: model,
      );
}

extension PeriodReviewX on PeriodReview {
  PeriodReviewsCompanion toCompanion() => PeriodReviewsCompanion.insert(
        id: id,
        period: period,
        periodStart: periodStart,
        periodEnd: periodEnd,
        generatedAt: generatedAt,
        headline: Value(headline),
        narrative: Value(narrative),
        wins: Value(wins),
        attentionAreas: Value(attentionAreas),
        recommendations: Value(recommendations),
        metrics: Value(metrics),
        citations: Value(citations),
        model: Value(model),
      );
}

extension LifeScoreRowX on LifeScoreRow {
  LifeScore toEntity() => LifeScore(
        computedAt: computedAt,
        habits: habits,
        health: health,
        finances: finances,
        productivity: productivity,
        mood: mood,
        missingPillars: missingPillars,
      );
}
