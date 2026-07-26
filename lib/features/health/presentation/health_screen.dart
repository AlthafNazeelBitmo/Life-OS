import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/extensions/date_time_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/health_metric.dart';

final StreamProvider<DailyHealthSummary> todayHealthProvider =
    StreamProvider<DailyHealthSummary>(
  (ref) => ref.watch(healthRepositoryProvider).watchDay(DateTime.now()),
);

final FutureProviderFamily<Map<String, double>, HealthKind> _seriesProvider =
    FutureProvider.family<Map<String, double>, HealthKind>((ref, kind) async {
  // Re-runs when today's summary changes, so logging a glass of water updates
  // the chart immediately.
  ref.watch(todayHealthProvider);
  final now = DateTime.now();
  final result = await ref.watch(healthRepositoryProvider).series(
        kind,
        from: now.subtract(const Duration(days: 30)),
        to: now.endOfDay,
      );
  return result.valueOrNull ?? const <String, double>{};
});

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  HealthKind _charted = HealthKind.sleep;

  Future<void> _log(HealthKind kind) async {
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Log ${kind.label.toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: kind.label,
            suffixText: kind.unit,
          ),
          onSubmitted: (raw) => Navigator.of(dialogContext).pop(
            double.tryParse(raw.replaceAll(',', '.')),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value == null || value <= 0) return;
    await ref.read(healthRepositoryProvider).increment(kind, value);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(todayHealthProvider).valueOrNull ??
        const DailyHealthSummary(dayKey: '');
    final series = ref.watch(_seriesProvider(_charted)).valueOrNull ?? const {};

    return AppBackdrop(
      accent: AppColors.health,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Health'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 100),
          children: <Widget>[
            GlassCard(
              accent: AppColors.health,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Today',
                    subtitle: 'Tap any metric to log it',
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.1,
                    children: <Widget>[
                      for (final kind in <HealthKind>[
                        HealthKind.sleep,
                        HealthKind.water,
                        HealthKind.exercise,
                        HealthKind.steps,
                        HealthKind.weight,
                        HealthKind.screenTime,
                      ])
                        StatTile(
                          label: kind.label,
                          value: summary.valueOf(kind) == null
                              ? '—'
                              : summary
                                  .valueOf(kind)!
                                  .toStringAsFixed(kind == HealthKind.weight ? 1 : 0),
                          unit: kind.unit,
                          progress: kind.defaultTarget > 0
                              ? summary.progressOf(kind)
                              : null,
                          accent: _accentFor(kind),
                          onTap: () => _log(kind),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Gap.h16,
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: 'Last 30 days'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final kind in <HealthKind>[
                          HealthKind.sleep,
                          HealthKind.exercise,
                          HealthKind.steps,
                          HealthKind.water,
                          HealthKind.weight,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: Gap.xs),
                            child: ChoiceChip(
                              label: Text(kind.label),
                              selected: _charted == kind,
                              onSelected: (_) =>
                                  setState(() => _charted = kind),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  SizedBox(
                    height: 170,
                    child: series.length < 2
                        ? Center(
                            child: Text(
                              'Log a few days to see a trend.',
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _HealthChart(
                            series: series,
                            kind: _charted,
                            color: _accentFor(_charted),
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

  static Color _accentFor(HealthKind kind) => switch (kind) {
        HealthKind.sleep => AppColors.insights,
        HealthKind.water => AppColors.calendar,
        HealthKind.exercise => AppColors.habits,
        HealthKind.steps => AppColors.goals,
        HealthKind.weight => AppColors.people,
        HealthKind.screenTime => AppColors.mood,
        HealthKind.calories => AppColors.finance,
        HealthKind.heartRate => AppColors.health,
      };
}

class _HealthChart extends StatelessWidget {
  const _HealthChart({
    required this.series,
    required this.kind,
    required this.color,
  });

  final Map<String, double> series;
  final HealthKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final days = series.keys.toList()..sort();
    final spots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), series[days[i]]!),
    ];
    final target = kind.defaultTarget;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          drawVerticalLine: false,
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
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: context.text.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
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
        // A dashed target line turns the chart from "a number over time" into
        // "am I where I want to be".
        extraLinesData: target > 0
            ? ExtraLinesData(
                horizontalLines: <HorizontalLine>[
                  HorizontalLine(
                    y: target,
                    color: context.colors.outline,
                    strokeWidth: 1,
                    dashArray: <int>[6, 4],
                  ),
                ],
              )
            : const ExtraLinesData(),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 2.5,
            color: color,
            dotData: FlDotData(show: spots.length < 20),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
