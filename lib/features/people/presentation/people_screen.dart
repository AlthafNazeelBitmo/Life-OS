import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/person.dart';

final StreamProvider<List<Person>> peopleProvider = StreamProvider<List<Person>>(
  (ref) => ref.watch(peopleRepositoryProvider).watchPeople(),
);

final FutureProvider<List<Person>> birthdaysProvider =
    FutureProvider<List<Person>>(
  (ref) async =>
      (await ref.watch(peopleRepositoryProvider).birthdaysWithin(30))
          .valueOrNull ??
      const <Person>[],
);

/// Relationship tracker.
///
/// The point is not a contact list — the phone already has one — but the things
/// worth remembering about people and a nudge before too long passes.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final birthdays = ref.watch(birthdaysProvider).valueOrNull ?? const [];

    return AppBackdrop(
      accent: AppColors.people,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('People'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'person-fab',
          onPressed: () => _addPerson(context, ref),
          icon: const Icon(Icons.person_add_alt_rounded),
          label: const Text('Add'),
        ),
        body: AsyncView<List<Person>>(
          value: people,
          builder: (context, items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No one added yet',
                message: 'Keep track of the details you always forget, and get '
                    'a nudge when it has been a while.',
                action: FilledButton(
                  onPressed: () => _addPerson(context, ref),
                  child: const Text('Add someone'),
                ),
              );
            }

            final overdue = items.where((person) => person.needsFollowUp).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              children: <Widget>[
                if (birthdays.isNotEmpty) ...<Widget>[
                  GlassCard(
                    accent: AppColors.mood,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionHeader(title: 'Birthdays coming up'),
                        for (final person in birthdays.take(4))
                          Text(
                            '🎂 ${person.name} · '
                            '${Fmt.shortDate(person.nextBirthday!)}',
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Gap.h16,
                ],
                if (overdue.isNotEmpty) ...<Widget>[
                  GlassCard(
                    accent: AppColors.caution,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionHeader(title: 'Worth a message'),
                        for (final person in overdue.take(5))
                          Text(
                            '${person.name} — '
                            '${person.daysSinceContact == null ? 'no contact logged' : '${person.daysSinceContact} days'}',
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Gap.h16,
                ],
                for (final person in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: GlassCard(
                      padding: Insets.cardCompact,
                      onTap: () =>
                          context.push(Routes.personDetailFor(person.id)),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            backgroundColor:
                                AppColors.people.withValues(alpha: 0.18),
                            child: Text(
                              person.name.isEmpty
                                  ? '?'
                                  : person.name[0].toUpperCase(),
                            ),
                          ),
                          Gap.w16,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  person.name,
                                  style: context.text.bodyMedium,
                                ),
                                Text(
                                  <String>[
                                    if (person.relation.isNotEmpty)
                                      person.relation,
                                    if (person.lastInteractionAt != null)
                                      'last ${Fmt.relative(person.lastInteractionAt!)}',
                                  ].join(' · '),
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (person.needsFollowUp)
                            Icon(
                              Icons.notifications_active_outlined,
                              size: 16,
                              color: context.colors.error,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final relation = TextEditingController();
    int? followUp;

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
                Text('Add someone', style: sheetContext.text.titleLarge),
                Gap.h16,
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                Gap.h12,
                TextField(
                  controller: relation,
                  decoration: const InputDecoration(
                    labelText: 'How do you know them?',
                  ),
                ),
                Gap.h16,
                Text(
                  'Remind me to check in every',
                  style: sheetContext.text.labelMedium,
                ),
                Gap.h8,
                Wrap(
                  spacing: Gap.xs,
                  children: <Widget>[
                    for (final days in <int>[7, 14, 30, 90])
                      ChoiceChip(
                        label: Text('$days days'),
                        selected: followUp == days,
                        onSelected: (_) => setSheetState(
                          () => followUp = followUp == days ? null : days,
                        ),
                      ),
                  ],
                ),
                Gap.h24,
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || name.text.trim().isEmpty) return;
    await ref.read(peopleRepositoryProvider).upsert(
          Person(
            id: newId(),
            name: name.text.trim(),
            createdAt: DateTime.now(),
            relation: relation.text.trim(),
            followUpEveryDays: followUp,
          ),
        );
  }
}
