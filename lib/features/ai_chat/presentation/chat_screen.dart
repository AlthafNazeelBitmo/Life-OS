import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/breakpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../domain/entities/chat.dart';
import '../application/chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.seedPrompt, super.key});

  /// Pre-filled question, used when the user arrives from an insight card.
  final String? seedPrompt;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(chatControllerProvider.notifier).openThread();
      final seed = widget.seedPrompt;
      if (seed != null && seed.isNotEmpty) await _send(seed);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
    if (!mounted || !_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final isLive = ref.watch(aiIsLiveProvider);

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Assistant'),
          actions: <Widget>[
            IconButton(
              tooltip: 'New conversation',
              onPressed: ref.read(chatControllerProvider.notifier).clear,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
          bottom: isLive
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(32),
                  child: _OfflineBanner(),
                ),
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: state.messages.isEmpty
                  ? _EmptyConversation(onPick: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(Gap.lg),
                      itemCount:
                          state.messages.length + (state.isThinking ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= state.messages.length) {
                          return const _ThinkingBubble();
                        }
                        return _MessageBubble(message: state.messages[index]);
                      },
                    ),
            ),
            _Composer(
              controller: _input,
              enabled: !state.isThinking,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: context.colors.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: Gap.lg),
        child: Text(
          'On-device mode — answers come from searching your own records.',
          style: context.text.labelSmall,
          textAlign: TextAlign.center,
        ),
      );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(Gap.xl),
        children: <Widget>[
          Gap.h32,
          Icon(
            Icons.auto_awesome_rounded,
            size: 40,
            color: context.colors.primary,
          ),
          Gap.h16,
          Text(
            'Ask about your life',
            style: context.text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          Gap.h8,
          Text(
            'Every answer is drawn from your own records, and shows which ones '
            'it used.',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          Gap.h32,
          for (final suggestion in chatSuggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: OutlinedButton(
                onPressed: () => onPick(suggestion),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(suggestion),
                ),
              ),
            ),
        ],
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final maxWidth = (context.screenSize.width * 0.82)
        .clamp(0.0, Breakpoints.maxContentWidth * 0.7);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.md,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? context.colors.primaryContainer
                      : context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(Radii.lg),
                    topRight: const Radius.circular(Radii.lg),
                    bottomLeft: Radius.circular(isUser ? Radii.lg : Radii.sm),
                    bottomRight: Radius.circular(isUser ? Radii.sm : Radii.lg),
                  ),
                ),
                child: SelectableText(
                  message.content,
                  style: context.text.bodyMedium?.copyWith(
                    color: isUser
                        ? context.colors.onPrimaryContainer
                        : context.colors.onSurface,
                  ),
                ),
              ),
              if (message.hasCitations) _Citations(citations: message.citations),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sources behind an answer, tappable through to the record itself.
///
/// This is the visible half of the "never hallucinate" contract: if the app
/// cannot show you where a claim came from, it does not present it as fact.
class _Citations extends StatelessWidget {
  const _Citations({required this.citations});

  final List<Citation> citations;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: <Widget>[
            for (final citation in citations.take(6))
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(_iconFor(citation.source), size: 14),
                label: Text(
                  citation.occurredAt == null
                      ? citation.label
                      : '${citation.label} · '
                          '${Fmt.shortDate(citation.occurredAt!)}',
                  style: context.text.labelSmall,
                ),
                onPressed: () => _open(context, citation),
              ),
          ],
        ),
      );

  static IconData _iconFor(CitationSource source) => switch (source) {
        CitationSource.journal => Icons.menu_book_outlined,
        CitationSource.mood => Icons.mood_outlined,
        CitationSource.habit => Icons.repeat_rounded,
        CitationSource.goal => Icons.flag_outlined,
        CitationSource.task => Icons.check_circle_outline,
        CitationSource.event => Icons.event_outlined,
        CitationSource.transaction => Icons.payments_outlined,
        CitationSource.health => Icons.favorite_outline,
        CitationSource.person => Icons.person_outline,
      };

  void _open(BuildContext context, Citation citation) {
    switch (citation.source) {
      case CitationSource.journal:
        context.push(Routes.journalEntryFor(citation.id));
      case CitationSource.goal:
        context.push(Routes.goalDetailFor(citation.id));
      case CitationSource.habit:
        context.push(Routes.habitDetailFor(citation.id));
      case CitationSource.person:
        context.push(Routes.personDetailFor(citation.id));
      case CitationSource.task:
        context.push(Routes.tasks);
      case CitationSource.event:
        context.push(Routes.calendar);
      case CitationSource.transaction:
        context.push(Routes.money);
      case CitationSource.mood:
        context.push(Routes.mood);
      case CitationSource.health:
        context.push(Routes.health);
    }
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              Gap.w12,
              Text('Reading your records…', style: context.text.bodySmall),
            ],
          ),
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: onSend,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your life…',
                  ),
                ),
              ),
              Gap.w8,
              IconButton.filled(
                onPressed: enabled ? () => onSend(controller.text) : null,
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      );
}
