import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_provider_type.dart';
import '../../../core/cache/key_value_store.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';

class _Page {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

const List<_Page> _pages = <_Page>[
  _Page(
    icon: Icons.auto_awesome_rounded,
    title: 'One place for your whole life',
    body: 'Journal, habits, goals, money, health and plans — together, so the '
        'connections between them are visible instead of guessed at.',
    color: AppColors.journal,
  ),
  _Page(
    icon: Icons.insights_rounded,
    title: 'Patterns, not just records',
    body: 'LifeOS looks for what actually moves your mood, sleep and focus, '
        'and shows you the records behind every claim.',
    color: AppColors.insights,
  ),
  _Page(
    icon: Icons.lock_outline_rounded,
    title: 'Yours, and offline first',
    body: 'Everything is stored on your device. Cloud sync and AI are both '
        'optional, and you choose which AI provider — if any.',
    color: AppColors.habits,
  ),
];

/// Sets the two things that genuinely change behaviour later: what the user
/// wants out of the app, and how private they want the AI to be. Everything
/// else can be discovered.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  final Set<String> _focusAreas = <String>{};

  static const List<String> _availableFocus = <String>[
    'Health',
    'Focus',
    'Money',
    'Relationships',
    'Learning',
    'Creativity',
    'Career',
    'Rest',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    // Stored in the cache rather than the profile: onboarding runs before
    // sign-in, so there is no profile to attach these to yet.
    await ref.read(keyValueStoreProvider).setJson(
      CacheKeys.focusAreas,
      <String, dynamic>{'areas': _focusAreas.toList()},
    );
    await ref.read(settingsProvider.notifier).completeOnboarding();
  }

  void _next() {
    if (_index < _pages.length) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _pages.length + 1; // + the focus-area picker

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (index) => setState(() => _index = index),
                  children: <Widget>[
                    for (final page in _pages) _IntroPage(page: page),
                    _FocusPage(
                      options: _availableFocus,
                      selected: _focusAreas,
                      onToggle: (value) => setState(() {
                        if (!_focusAreas.remove(value)) _focusAreas.add(value);
                      }),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (var i = 0; i < totalPages; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: 6,
                            width: i == _index ? 22 : 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.pill),
                              color: i == _index
                                  ? context.colors.primary
                                  : context.colors.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                    Gap.h24,
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        child: Text(
                          _index == totalPages - 1 ? 'Get started' : 'Next',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(Gap.xl),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: page.color.withValues(alpha: 0.14),
              ),
              child: Icon(page.icon, size: 44, color: page.color),
            ),
            Gap.h32,
            Text(
              page.title,
              style: context.text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Gap.h16,
            Text(
              page.body,
              style: context.text.bodyLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _FocusPage extends ConsumerWidget {
  const _FocusPage({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Gap.h24,
          Text('What matters right now?', style: context.text.headlineMedium),
          Gap.h8,
          Text(
            'This shapes what the dashboard leads with. You can change it later.',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Gap.h24,
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: <Widget>[
              for (final option in options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (_) => onToggle(option),
                ),
            ],
          ),
          Gap.h32,
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.shield_outlined, size: 18),
                    Gap.w8,
                    Text('AI privacy', style: context.text.titleSmall),
                  ],
                ),
                Gap.h8,
                Text(
                  'LifeOS works fully without an AI service. If you connect one, '
                  'only the records needed to answer a question are sent — and '
                  'you can pick a local model instead.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                Gap.h12,
                SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: AiProviderType.offline.id,
                      label: const Text('On-device'),
                      icon: const Icon(Icons.phone_iphone_rounded),
                    ),
                    ButtonSegment<String>(
                      value: AiProviderType.openai.id,
                      label: const Text('Cloud AI'),
                      icon: const Icon(Icons.cloud_outlined),
                    ),
                  ],
                  selected: <String>{
                    settings.aiProviderId == AiProviderType.offline.id
                        ? AiProviderType.offline.id
                        : AiProviderType.openai.id,
                  },
                  onSelectionChanged: (values) => ref
                      .read(settingsProvider.notifier)
                      .setAiProvider(values.first),
                ),
                Gap.h8,
                Text(
                  'Add your API key later in Settings › AI.',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Gap.h24,
        ],
      ),
    );
  }
}
