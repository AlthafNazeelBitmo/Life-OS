import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_x.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../services/voice/voice_input_service.dart';

/// The floating assistant.
///
/// Tap opens the chat; press-and-hold captures voice. Both live on one control
/// because they are the same intent — "tell the app something" — and a second
/// button would compete with the module FABs on every screen.
class AssistantFab extends ConsumerWidget {
  const AssistantFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceInputProvider);
    final listening = voice.status == VoiceStatus.listening;

    ref.listen(voiceInputProvider, (previous, next) {
      if (next.status == VoiceStatus.done && next.result != null) {
        context.showSnack(next.result!);
      } else if (next.status == VoiceStatus.error && next.message != null) {
        context.showError(next.message!);
      }
    });

    return Semantics(
      button: true,
      label: listening ? 'Listening. Release to save.' : 'Assistant',
      child: GestureDetector(
        onLongPressStart: (_) =>
            ref.read(voiceInputProvider.notifier).startListening(),
        onLongPressEnd: (_) =>
            ref.read(voiceInputProvider.notifier).stopListening(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (listening || voice.status == VoiceStatus.processing)
              _LiveCaption(voice: voice),
            FloatingActionButton(
              heroTag: 'assistant-fab',
              onPressed: () => context.push(Routes.chat),
              tooltip: 'Ask the assistant · hold to speak',
              backgroundColor:
                  listening ? context.colors.error : context.colors.primary,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  listening ? Icons.mic_rounded : Icons.auto_awesome_rounded,
                  key: ValueKey<bool>(listening),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveCaption extends StatelessWidget {
  const _LiveCaption({required this.voice});

  final VoiceState voice;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 260),
        margin: const EdgeInsets.only(bottom: Gap.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        decoration: BoxDecoration(
          color: context.colors.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          voice.status == VoiceStatus.processing
              ? 'Working out what to save…'
              : (voice.transcript.isEmpty ? 'Listening…' : voice.transcript),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onInverseSurface,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
