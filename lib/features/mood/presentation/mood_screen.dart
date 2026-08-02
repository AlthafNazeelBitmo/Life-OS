import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/mood_entry.dart';
import '../../../domain/repositories/mood_repository.dart';

final StreamProvider<List<MoodEntry>> _recentMoodProvider =
    StreamProvider<List<MoodEntry>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(moodRepositoryProvider)
      .watchRange(now.subtract(const Duration(days: 30)), now.endOfDay);
});

final FutureProvider<List<MoodCorrelation>> _correlationsProvider =
    FutureProvider<List<MoodCorrelation>>(
  (ref) async =>
      (await ref.watch(moodRepositoryProvider).correlations()).valueOrNull ??
      const <MoodCorrelation>[],
);

/// Check-in, trends and the patterns behind them.
class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({super.key});

  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  final Map<MoodDimension, int> _values = <MoodDimension, int>{
    for (final dimension in MoodDimension.values) dimension: 5,
  };
  MoodDimension _charted = MoodDimension.happiness;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final result = await ref.read(moodRepositoryProvider).upsert(
          MoodEntry(
            id: newId(),
            recordedAt: now,
            dayKey: Fmt.dayKey(now),
            happiness: _values[MoodDimension.happiness]!,
            energy: _values[MoodDimension.energy]!,
            focus: _values[MoodDimension.focus]!,
            productivity: _values[MoodDimension.productivity]!,
            stress: _values[MoodDimension.stress]!,
            anxiety: _values[MoodDimension.anxiety]!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        );
    if (!mounted) return;
    result.fold(
      (_) {
        _note.clear();
        context.showSnack('Checked in');
        ref.invalidate(_correlationsProvider);
      },
      (failure) => context.showError(failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(_recentMoodProvider).valueOrNull ?? const [];
    final correlations = ref.watch(_correlationsProvider).valueOrNull ?? const [];

    return AppBackdrop(
      accent: AppColors.mood,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Mood'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 100),
          children: <Widget>[
            GlassCard(
              accent: AppColors.mood,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Check in',
                    subtitle: 'Takes about fifteen seconds',
                  ),
                  for (final dimension in MoodDimension.values)
                    _DimensionSlider(
                      dimension: dimension,
                      value: _values[dimension]!,
                      onChanged: (value) =>
                          setState(() => _values[dimension] = value),
                    ),
                  Gap.h12,
                  TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Anything worth noting?',
                    ),
                  ),
                  Gap.h16,
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save check-in'),
                    ),
                  ),
                ],
              ),
            ),
            Gap.h16,
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Last 30 days',
                    subtitle: 'Daily averages',
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final dimension in MoodDimension.values)
                          Padding(
                            padding: const EdgeInsets.only(right: Gap.xs),
                            child: ChoiceChip(
                              label: Text(dimension.label),
                              selected: _charted == dimension,
                              onSelected: (_) =>
                                  setState(() => _charted = dimension),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  SizedBox(
                    height: 180,
                    child: recent.length < 2
                        ? Center(
                            child: Text(
                              'Check in a few times to see a trend.',
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _MoodChart(entries: recent, dimension: _charted),
                  ),
                ],
              ),
            ),
            if (correlations.isNotEmpty) ...<Widget>[
              Gap.h16,
              GlassCard(
                accent: AppColors.insights,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionHeader(
                      title: 'What moves your mood',
                      subtitle: 'Computed on this device from your own logs',
                    ),
                    for (final correlation
                        in correlations.where((c) => c.isMeaningful).take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              correlation.coefficient > 0
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 16,
                              color: correlation.coefficient > 0
                                  ? AppColors.positive
                                  : AppColors.negative,
                            ),
                            Gap.w8,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    correlation.description,
                                    style: context.text.bodySmall,
                                  ),
                                  Text(
                                    'r = ${correlation.coefficient.toStringAsFixed(2)} '
                                    'over ${correlation.sampleSize} days',
                                    style: context.text.labelSmall?.copyWith(
                                      color: context.colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Correlation is not causation — these are prompts to '
                      'look closer, not conclusions.',
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DimensionSlider extends StatelessWidget {
  const _DimensionSlider({
    required this.dimension,
    required this.value,
    required this.onChanged,
  });

  final MoodDimension dimension;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              dimension.label,
              style: context.text.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '$value',
              // Semantics matter here: a screen reader user needs the
              // dimension name, not just a number.
              semanticFormatterCallback: (v) =>
                  '${dimension.label} ${v.round()} out of 10',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text('$value', style: context.text.labelLarge),
          ),
        ],
      );
}

class _MoodChart extends StatelessWidget {
  const _MoodChart({required this.entries, required this.dimension});

  final List<MoodEntry> entries;
  final MoodDimension dimension;

  @override
  Widget build(BuildContext context) {
    // Average per day so several check-ins in one day count once.
    final byDay = <String, List<int>>{};
    for (final entry in entries) {
      byDay
          .putIfAbsent(entry.dayKey, () => <int>[])
          .add(entry.valueOf(dimension));
    }
    final days = byDay.keys.toList()..sort();
    final spots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(
          i.toDouble(),
          byDay[days[i]]!.reduce((a, b) => a + b) / byDay[days[i]]!.length,
        ),
    ];

    return LineChart(
      LineChartData(
        minY: 1,
        maxY: 10,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.colors.outlineVariant,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: context.text.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (days.length / 4).clamp(1, 30).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= days.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  Fmt.shortDate(Fmt.parseDayKey(days[index])).substring(0, 6),
                  style: context.text.labelSmall,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            barWidth: 2.5,
            color: AppColors.mood,
            dotData: FlDotData(show: spots.length < 20),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.mood.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
