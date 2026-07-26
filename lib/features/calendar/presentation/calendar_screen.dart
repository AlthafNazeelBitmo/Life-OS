import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/calendar_event.dart';

/// Events for the visible month, keyed by day for the calendar markers.
final StreamProviderFamily<List<CalendarEvent>, DateTime> monthEventsProvider =
    StreamProvider.family<List<CalendarEvent>, DateTime>(
  (ref, month) => ref.watch(calendarRepositoryProvider).watchRange(
        month.startOfMonth.subtract(const Duration(days: 7)),
        month.endOfMonth.add(const Duration(days: 7)),
      ),
);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  Future<void> _createEvent(DateTime day) async {
    final title = TextEditingController();
    var start = day.withTime(9, 0);
    var kind = EventKind.event;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Padding(
            padding: Insets.sheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('New event', style: sheetContext.text.titleLarge),
                Gap.h16,
                TextField(
                  controller: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                Gap.h16,
                Wrap(
                  spacing: Gap.xs,
                  children: <Widget>[
                    for (final option in EventKind.values)
                      ChoiceChip(
                        label: Text(option.name),
                        selected: kind == option,
                        onSelected: (_) => setSheetState(() => kind = option),
                      ),
                  ],
                ),
                Gap.h12,
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: sheetContext,
                      initialTime: TimeOfDay.fromDateTime(start),
                    );
                    if (picked != null) {
                      setSheetState(
                        () => start = day.withTime(picked.hour, picked.minute),
                      );
                    }
                  },
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(Fmt.time(start)),
                ),
                Gap.h24,
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || title.text.trim().isEmpty) return;
    await ref.read(calendarRepositoryProvider).upsert(
          CalendarEvent(
            id: newId(),
            title: title.text.trim(),
            start: start,
            end: start.add(const Duration(hours: 1)),
            createdAt: DateTime.now(),
            kind: kind,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final events =
        ref.watch(monthEventsProvider(_focused)).valueOrNull ?? const [];
    final weekStartsMonday =
        ref.watch(settingsProvider.select((s) => s.weekStartsMonday));

    final dayEvents = events
        .where((event) => event.start.isSameDay(_selected))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return AppBackdrop(
      accent: AppColors.calendar,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Calendar'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Today',
              onPressed: () => setState(() {
                _focused = DateTime.now();
                _selected = DateTime.now();
              }),
              icon: const Icon(Icons.today_rounded),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'event-fab',
          onPressed: () => _createEvent(_selected),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Event'),
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: Insets.page,
              child: GlassCard(
                padding: Insets.cardCompact,
                child: TableCalendar<CalendarEvent>(
                  firstDay: DateTime(2015),
                  lastDay: DateTime(2100),
                  focusedDay: _focused,
                  currentDay: DateTime.now(),
                  calendarFormat: _format,
                  startingDayOfWeek: weekStartsMonday
                      ? StartingDayOfWeek.monday
                      : StartingDayOfWeek.sunday,
                  selectedDayPredicate: (day) => day.isSameDay(_selected),
                  eventLoader: (day) =>
                      events.where((event) => event.start.isSameDay(day)).toList(),
                  onDaySelected: (selected, focused) => setState(() {
                    _selected = selected;
                    _focused = focused;
                  }),
                  onFormatChanged: (format) => setState(() => _format = format),
                  onPageChanged: (focused) => setState(() => _focused = focused),
                  headerStyle: HeaderStyle(
                    formatButtonShowsNext: false,
                    titleCentered: true,
                    titleTextStyle: context.text.titleMedium ??
                        const TextStyle(fontSize: 16),
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: context.colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                      color: context.colors.onPrimaryContainer,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: context.colors.primary,
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: BoxDecoration(
                      color: AppColors.calendar,
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 3,
                  ),
                ),
              ),
            ),
            Expanded(
              child: dayEvents.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing on ${Fmt.shortDate(_selected)}',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.lg,
                        0,
                        Gap.lg,
                        120,
                      ),
                      itemCount: dayEvents.length,
                      itemBuilder: (context, index) =>
                          _EventTile(event: dayEvents[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: GlassCard(
          padding: Insets.cardCompact,
          accent: Color(event.colorValue),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 58,
                child: Text(
                  event.allDay ? 'All day' : Fmt.time(event.start),
                  style: context.text.labelMedium,
                ),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(event.title, style: context.text.bodyMedium),
                    if (event.location.isNotEmpty)
                      Text(
                        event.location,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (event.isAiScheduled)
                Tooltip(
                  message: 'Scheduled by the assistant',
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(calendarRepositoryProvider).delete(event.id),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
      );
}
