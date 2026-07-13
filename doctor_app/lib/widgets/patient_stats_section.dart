import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/patient_stats.dart';
import '../providers/auth_provider.dart';

final patientStatsProvider =
    FutureProvider.family<PatientStats, int>((ref, patientId) async {
  final api = ref.watch(apiClientProvider);
  return PatientStats.fromJson(await api.getPatientStats(patientId));
});

final _dayFormat = DateFormat('dd.MM');

/// Блок статистики на карточке пациента: динамика, ошибки по звукам,
/// приверженность.
class PatientStatsSection extends ConsumerWidget {
  final int patientId;
  const PatientStatsSection({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(patientStatsProvider(patientId));

    return statsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Ошибка загрузки статистики: $e'),
      data: (stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdherenceCard(adherence: stats.adherence),
          const SizedBox(height: 16),
          _DynamicsCard(points: stats.dynamics),
          const SizedBox(height: 16),
          _SoundErrorsCard(sounds: stats.soundErrors),
        ],
      ),
    );
  }
}

// ─── Приверженность ──────────────────────────────────────────────────────

class _AdherenceCard extends StatelessWidget {
  final Adherence adherence;
  const _AdherenceCard({required this.adherence});

  @override
  Widget build(BuildContext context) {
    final avg = adherence.avgCompletionDays;
    return Card(
      key: const Key('stats_adherence'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Приверженность',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  label: 'Пройдено',
                  value: '${adherence.completed}',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
                _StatTile(
                  label: 'Назначено',
                  value: '${adherence.assigned}',
                  icon: Icons.assignment_outlined,
                ),
                _StatTile(
                  label: 'Просрочено',
                  value: '${adherence.expired}',
                  icon: Icons.schedule,
                  color: adherence.expired > 0 ? Colors.orange : null,
                ),
                _StatTile(
                  label: 'Ожидают',
                  value: '${adherence.upcoming}',
                  icon: Icons.hourglass_empty,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              avg == null
                  ? 'Нет данных о скорости прохождения'
                  : 'В среднем проходит за ${_days(avg)} после назначения',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _days(double d) {
    final rounded = d == d.roundToDouble() ? d.round().toString() : d.toString();
    final n = d.round();
    final word = (n % 10 == 1 && n % 100 != 11)
        ? 'день'
        : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20))
            ? 'дня'
            : 'дней';
    return '$rounded $word';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MaterialColor? color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Статус-цвет только когда он что-то значит (просрочка, успех); иначе —
    // нейтральная поверхность. Цвет всегда идёт вместе с иконкой и подписью.
    final fg = color?[700] ?? scheme.onSurfaceVariant;
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Динамика результатов ────────────────────────────────────────────────

class _DynamicsCard extends StatelessWidget {
  final List<StatsPoint> points;
  const _DynamicsCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('stats_dynamics'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Динамика результатов',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Доля правильных ответов, %',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            _body(context),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (points.isEmpty) {
      return const Text('Пациент ещё не прошёл ни одного теста');
    }
    // Одна точка — это не график, а число.
    if (points.length == 1) {
      final p = points.first;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('${p.percent.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${p.quizTitle} · ${p.score} из ${p.total} · ${_dayFormat.format(p.submittedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    return SizedBox(height: 220, child: _LineChart(points: points));
  }
}

class _LineChart extends StatelessWidget {
  final List<StatsPoint> points;
  const _LineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grid = scheme.outlineVariant;
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        // Сетка приглушённая — данные на переднем плане.
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 36,
              getTitlesWidget: (value, _) =>
                  Text('${value.toInt()}', style: labelStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length || i != value) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dayFormat.format(points[i].submittedAt.toLocal()),
                    style: labelStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final p = points[s.x.toInt()];
              return LineTooltipItem(
                '${p.quizTitle}\n${p.percent.toStringAsFixed(0)}% · ${p.score} из ${p.total}',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].percent),
            ],
            isCurved: false,
            barWidth: 2,
            color: scheme.primary,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: scheme.primary,
                // Кольцо цвета поверхности — точки не сливаются с линией.
                strokeWidth: 2,
                strokeColor: scheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ошибки по звукам ────────────────────────────────────────────────────

class _SoundErrorsCard extends StatelessWidget {
  final List<SoundError> sounds;
  const _SoundErrorsCard({required this.sounds});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('stats_sound_errors'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ошибки по звукам',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Доля неверных ответов по каждому звуку, %',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (sounds.isEmpty)
              const Text('Нет данных — пациент не проходил тестов со звуками')
            else
              ...sounds.map((s) => _SoundBar(sound: s)),
          ],
        ),
      ),
    );
  }
}

/// Горизонтальный бар: одна серия — один цвет. Длина уже кодирует величину,
/// поэтому красить бары по значению не нужно.
class _SoundBar extends StatelessWidget {
  final SoundError sound;
  const _SoundBar({required this.sound});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = sound.isDeleted ? '${sound.title} (удалён)' : sound.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sound.category == null ? title : '$title · ${sound.category}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: sound.isDeleted
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              // Прямая подпись значения — легенда не нужна.
              Text(
                '${sound.errorPercent.toStringAsFixed(0)}%  '
                '(${sound.errors} из ${sound.answered})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (sound.errorPercent / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
