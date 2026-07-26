import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
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

final StreamProviderFamily<Person?, String> _personProvider =
    StreamProvider.family<Person?, String>(
  (ref, id) => ref.watch(peopleRepositoryProvider).watchPerson(id),
);

final StreamProviderFamily<List<Interaction>, String> _interactionsProvider =
    StreamProvider.family<List<Interaction>, String>(
  (ref, id) => ref.watch(peopleRepositoryProvider).watchInteractions(id),
);

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(_personProvider(personId));
    final interactions =
        ref.watch(_interactionsProvider(personId)).valueOrNull ?? const [];

    return AppBackdrop(
      accent: AppColors.people,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(person.valueOrNull?.name ?? 'Person'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'interaction-fab',
          onPressed: () => _logInteraction(context, ref),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('Log a catch-up'),
        ),
        body: AsyncView<Person?>(
          value: person,
          builder: (context, value) {
            if (value == null) {
              return const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Person not found',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
              children: <Widget>[
                GlassCard(
                  accent: AppColors.people,
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            AppColors.people.withValues(alpha: 0.18),
                        child: Text(
                          value.name.isEmpty
                              ? '?'
                              : value.name[0].toUpperCase(),
                          style: context.text.titleLarge,
                        ),
                      ),
                      Gap.w16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(value.name, style: context.text.titleMedium),
                            if (value.relation.isNotEmpty)
                              Text(
                                value.relation,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            if (value.nextBirthday != null)
                              Text(
                                '🎂 ${Fmt.shortDate(value.nextBirthday!)}',
                                style: context.text.labelSmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (value.details.isNotEmpty) ...<Widget>[
                  Gap.h16,
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionHeader(
                          title: 'Worth remembering',
                          subtitle: 'Shown before your next meeting',
                        ),
                        for (final detail in value.details)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $detail',
                              style: context.text.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                Gap.h16,
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'History',
                        subtitle: value.daysSinceContact == null
                            ? 'Nothing logged yet'
                            : 'Last contact ${value.daysSinceContact} days ago',
                      ),
                      if (interactions.isEmpty)
                        Text(
                          'Log a catch-up to start building the history.',
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final interaction in interactions)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              switch (interaction.channel) {
                                InteractionChannel.call => Icons.call_outlined,
                                InteractionChannel.message =>
                                  Icons.chat_bubble_outline,
                                InteractionChannel.email =>
                                  Icons.mail_outline_rounded,
                                InteractionChannel.video =>
                                  Icons.videocam_outlined,
                                InteractionChannel.inPerson =>
                                  Icons.people_outline,
                                InteractionChannel.other =>
                                  Icons.more_horiz_rounded,
                              },
                              size: 18,
                            ),
                            title: Text(
                              interaction.summary.isEmpty
                                  ? interaction.channel.name
                                  : interaction.summary,
                            ),
                            subtitle: Text(
                              Fmt.shortDate(interaction.occurredAt),
                              style: context.text.labelSmall,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _logInteraction(BuildContext context, WidgetRef ref) async {
    final summary = TextEditingController();
    var channel = InteractionChannel.inPerson;

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
                Text('Log a catch-up', style: sheetContext.text.titleLarge),
                Gap.h16,
                Wrap(
                  spacing: Gap.xs,
                  children: <Widget>[
                    for (final option in InteractionChannel.values)
                      ChoiceChip(
                        label: Text(option.name),
                        selected: channel == option,
                        onSelected: (_) =>
                            setSheetState(() => channel = option),
                      ),
                  ],
                ),
                Gap.h16,
                TextField(
                  controller: summary,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What did you talk about?',
                  ),
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

    if (confirmed != true) return;
    await ref.read(peopleRepositoryProvider).logInteraction(
          Interaction(
            id: newId(),
            personId: personId,
            occurredAt: DateTime.now(),
            channel: channel,
            summary: summary.text.trim(),
          ),
        );
  }
}
