import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/stats_repository.dart';
import '../widgets/common.dart';

/// Статистика: все значения считаются SQL-запросами в StatsRepository.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<StatsRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: StreamBuilder<DashboardStats>(
        stream: repo.watch(),
        builder: (context, snap) {
          final s = snap.data;
          if (s == null)
            return const Center(child: CircularProgressIndicator());
          final maxPrio = s.byPriority.values.fold<int>(
            1,
            (a, b) => b > a ? b : a,
          );
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _Kpi(
                    'Проектов',
                    s.projects,
                    Icons.folder_outlined,
                    Colors.indigo,
                  ),
                  _Kpi(
                    'Всего задач',
                    s.totalTasks,
                    Icons.list_alt,
                    Colors.blue,
                  ),
                  _Kpi(
                    'Завершено',
                    s.doneTasks,
                    Icons.check_circle_outline,
                    Colors.green,
                  ),
                  _Kpi(
                    'Не завершено',
                    s.openTasks,
                    Icons.timelapse,
                    Colors.orange,
                  ),
                  _Kpi(
                    'Просрочено',
                    s.overdueTasks,
                    Icons.warning_amber,
                    Colors.red,
                  ),
                ],
              ),
              const SectionTitle('Задачи по приоритетам'),
              for (final p in TaskPriority.values)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(p.label)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (s.byPriority[p] ?? 0) / maxPrio,
                          minHeight: 12,
                          color: priorityColor(p),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${s.byPriority[p]}',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              const SectionTitle('Задачи по исполнителям'),
              if (s.byAssignee.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Нет назначенных задач'),
                ),
              for (final a in s.byAssignee.take(15))
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      initials(a.name),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(a.name),
                  trailing: Text(
                    '${a.count}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              const SectionTitle('Выполнение проектов'),
              for (final p in s.projectProgress)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.project.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${p.percent.toStringAsFixed(0)}%',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: p.percent / 100,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}
