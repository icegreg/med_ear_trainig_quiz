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
final _dateFormat = DateFormat('dd.MM.yyyy');
final _dateTimeFormat = DateFormat('dd.MM.yyyy, HH:mm');

/// Русская локаль intl в приложении не инициализирована — свои сокращения.
const _monthNames = [
  'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

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
          // Календарь первым: «заходит ли он вообще» — вопрос до результатов.
          _ActivityCard(activity: stats.activity),
          const SizedBox(height: 16),
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

// ─── Календарь активности ────────────────────────────────────────────────

/// Сколько недель показываем. Полгода — видно и регулярность, и провалы,
/// и при этом сетка влезает на экран без прокрутки на типичном мониторе.
const _weeksShown = 26;
const _cellSize = 13.0;
const _cellGap = 3.0;

/// Heatmap прохождений: недели по горизонтали, дни недели по вертикали.
class _ActivityCard extends StatelessWidget {
  final Activity activity;
  const _ActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final counts = activity.byDate;
    // Сетка заканчивается текущей неделей; отсчитываем назад до понедельника.
    final today = DateUtils.dateOnly(DateTime.now());
    final lastMonday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday =
        lastMonday.subtract(const Duration(days: 7 * (_weeksShown - 1)));

    return Card(
      key: const Key('stats_activity'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Активность', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Пройденные тесты за последние полгода',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MonthLabels(firstMonday: firstMonday),
                  const SizedBox(height: 4),
                  _Heatmap(
                    firstMonday: firstMonday,
                    today: today,
                    counts: counts,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _HeatmapLegend(),
            const SizedBox(height: 12),
            Text(
              activity.lastSeenAt == null
                  ? 'Приложение ещё ни разу не выходило на связь'
                  : 'Последний вход: '
                      '${_dateTimeFormat.format(activity.lastSeenAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final DateTime firstMonday;
  final DateTime today;
  final Map<DateTime, int> counts;

  const _Heatmap({
    required this.firstMonday,
    required this.today,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var week = 0; week < _weeksShown; week++)
          Padding(
            padding: const EdgeInsets.only(right: _cellGap),
            child: Column(
              children: [
                for (var day = 0; day < 7; day++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _cellGap),
                    child: _DayCell(
                      date: firstMonday.add(Duration(days: week * 7 + day)),
                      today: today,
                      counts: counts,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final DateTime today;
  final Map<DateTime, int> counts;

  const _DayCell({
    required this.date,
    required this.today,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    // Дни после сегодняшнего в текущей неделе — не данные, а пустое место.
    if (date.isAfter(today)) {
      return const SizedBox(width: _cellSize, height: _cellSize);
    }
    final quizzes = counts[date] ?? 0;
    return Tooltip(
      message: '${_dateFormat.format(date)} — ${_quizzesWord(quizzes)}',
      child: Container(
        width: _cellSize,
        height: _cellSize,
        decoration: BoxDecoration(
          color: _cellColor(Theme.of(context).colorScheme, quizzes),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Последовательная шкала: один цвет, светлее → темнее. Ноль — нейтральная
/// поверхность, а не бледный оттенок цвета: «не заходил» это не «мало».
Color _cellColor(ColorScheme scheme, int quizzes) {
  if (quizzes <= 0) return scheme.surfaceContainerHighest;
  if (quizzes == 1) return scheme.primary.withOpacity(0.35);
  if (quizzes == 2) return scheme.primary.withOpacity(0.65);
  return scheme.primary;
}

String _quizzesWord(int n) {
  if (n == 0) return 'тестов не было';
  final word = (n % 10 == 1 && n % 100 != 11)
      ? 'тест'
      : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20))
          ? 'теста'
          : 'тестов';
  return '$n $word';
}

class _MonthLabels extends StatelessWidget {
  final DateTime firstMonday;
  const _MonthLabels({required this.firstMonday});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    var previousMonth = -1;

    return Row(
      children: [
        for (var week = 0; week < _weeksShown; week++)
          Builder(builder: (_) {
            final monday = firstMonday.add(Duration(days: week * 7));
            // Подпись — только на первой неделе месяца, иначе они сольются.
            final isNewMonth = monday.month != previousMonth;
            previousMonth = monday.month;
            return SizedBox(
              width: _cellSize + _cellGap,
              child: isNewMonth
                  ? Text(
                      _monthNames[monday.month - 1],
                      style: style,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    )
                  : const SizedBox.shrink(),
            );
          }),
      ],
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Text('меньше', style: style),
        const SizedBox(width: 6),
        for (final quizzes in [0, 1, 2, 3])
          Padding(
            padding: const EdgeInsets.only(right: _cellGap),
            child: Container(
              width: _cellSize,
              height: _cellSize,
              decoration: BoxDecoration(
                color: _cellColor(scheme, quizzes),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        const SizedBox(width: 3),
        Text('больше', style: style),
      ],
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
