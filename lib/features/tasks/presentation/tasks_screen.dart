import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/task.dart';

final StreamProvider<List<Task>> allTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

/// Kanban board plus a list view.
///
/// Drag-and-drop writes through `TaskRepository.reorder`, which rewrites the
/// whole column's order in one transaction — so a drop can never leave two
/// tasks fighting over the same index.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _boardView = true;
  bool _prioritising = false;

  static const List<TaskStatus> _columns = <TaskStatus>[
    TaskStatus.today,
    TaskStatus.inProgress,
    TaskStatus.backlog,
    TaskStatus.done,
  ];

  static String _label(TaskStatus status) => switch (status) {
        TaskStatus.today => 'Today',
        TaskStatus.inProgress => 'In progress',
        TaskStatus.backlog => 'Backlog',
        TaskStatus.blocked => 'Blocked',
        TaskStatus.done => 'Done',
      };

  Future<void> _prioritise(List<Task> tasks) async {
    setState(() => _prioritising = true);
    final now = DateTime.now();

    final lifeContext = await ref.read(contextBuilderProvider).forRange(
          from: now.subtract(const Duration(days: 14)),
          to: now.endOfDay,
        );
    final plan = await ref.read(aiServiceProvider).planDay(
          date: now,
          tasks: tasks.where((task) => !task.isDone).toList(),
          context: lifeContext,
        );

    if (!mounted) return;
    await plan.fold(
      (value) async {
        // The plan's block order becomes the task order, with the model's own
        // reason attached so the UI can explain the ranking.
        final reasons = <String, String>{
          for (final block in value.blocks)
            if (block.taskId != null) block.taskId!: block.reason,
        };
        if (reasons.isEmpty) return;
        await ref.read(taskRepositoryProvider).applyPriorities(reasons);
        if (mounted) context.showSnack('Reordered by what matters today');
      },
      (failure) async => context.showError(failure.message),
    );
    if (mounted) setState(() => _prioritising = false);
  }

  Future<void> _addTask(TaskStatus status) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('New task in ${_label(status)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;

    await ref.read(taskRepositoryProvider).upsert(
          Task(
            id: newId(),
            title: title.trim(),
            createdAt: DateTime.now(),
            status: status,
            priority: TaskPriority.medium,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(allTasksProvider);

    return AppBackdrop(
      accent: AppColors.tasks,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Tasks'),
          actions: <Widget>[
            IconButton(
              tooltip: _boardView ? 'List view' : 'Board view',
              onPressed: () => setState(() => _boardView = !_boardView),
              icon: Icon(
                _boardView ? Icons.view_list_rounded : Icons.view_column_rounded,
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'task-fab',
          onPressed: () => _addTask(TaskStatus.today),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Task'),
        ),
        body: AsyncView<List<Task>>(
          value: tasks,
          builder: (context, items) => Column(
            children: <Widget>[
              Padding(
                padding: Insets.page,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${items.where((t) => !t.isDone).length} open · '
                        '${items.where((t) => t.isOverdue).length} overdue',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          _prioritising ? null : () => _prioritise(items),
                      icon: _prioritising
                          ? const SizedBox.square(
                              dimension: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Prioritise'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _boardView
                    ? _Board(
                        tasks: items,
                        columns: _columns,
                        labelOf: _label,
                        onAdd: _addTask,
                      )
                    : _TaskList(tasks: items),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({
    required this.tasks,
    required this.columns,
    required this.labelOf,
    required this.onAdd,
  });

  final List<Task> tasks;
  final List<TaskStatus> columns;
  final String Function(TaskStatus) labelOf;
  final ValueChanged<TaskStatus> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        children: <Widget>[
          for (final status in columns)
            SizedBox(
              width: 280,
              child: Padding(
                padding: const EdgeInsets.only(right: Gap.md),
                child: DragTarget<Task>(
                  onAcceptWithDetails: (details) => ref
                      .read(taskRepositoryProvider)
                      .reorder(
                        taskId: details.data.id,
                        toStatus: status,
                        toIndex: 0,
                      ),
                  builder: (context, candidate, rejected) => Container(
                    decoration: BoxDecoration(
                      borderRadius: Radii.cardRadius,
                      color: candidate.isEmpty
                          ? Colors.transparent
                          : context.colors.primaryContainer
                              .withValues(alpha: 0.4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(Gap.sm),
                          child: Row(
                            children: <Widget>[
                              Text(
                                labelOf(status),
                                style: context.text.titleSmall,
                              ),
                              Gap.w8,
                              Text(
                                '${tasks.where((t) => t.status == status).length}',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onAdd(status),
                                icon: const Icon(Icons.add_rounded, size: 18),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: <Widget>[
                              for (final task
                                  in tasks.where((t) => t.status == status))
                                Draggable<Task>(
                                  data: task,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: SizedBox(
                                      width: 260,
                                      child: _TaskCard(task: task),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: _TaskCard(task: task),
                                  ),
                                  child: _TaskCard(task: task),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: GlassCard(
          padding: Insets.cardCompact,
          accent: task.isOverdue ? context.colors.error : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      task.title,
                      style: context.text.bodyMedium?.copyWith(
                        decoration:
                            task.isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: task.isDone,
                    onChanged: (value) => ref
                        .read(taskRepositoryProvider)
                        .complete(task.id, done: value ?? false),
                  ),
                ],
              ),
              if (task.dueAt != null || task.priority != TaskPriority.none)
                Text(
                  <String>[
                    if (task.priority != TaskPriority.none) task.priority.label,
                    if (task.dueAt != null)
                      task.isOverdue
                          ? 'Overdue'
                          : Fmt.shortDate(task.dueAt!),
                  ].join(' · '),
                  style: context.text.labelSmall?.copyWith(
                    color: task.isOverdue
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              if (task.aiReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome_rounded, size: 12),
                      Gap.w4,
                      Expanded(
                        child: Text(
                          task.aiReason!,
                          style: context.text.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing on your list',
      );
    }
    final sorted = tasks.toList()
      ..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
      children: <Widget>[
        for (final task in sorted) _TaskCard(task: task),
      ],
    );
  }
}
