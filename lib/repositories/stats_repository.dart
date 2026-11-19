import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/views.dart';
import 'project_repository.dart';

/// Вся статистика считается SQL-запросами (COUNT / SUM / GROUP BY).
class StatsRepository {
  StatsRepository(this.db, this.projects);
  final AppDatabase db;
  final ProjectRepository projects;

  Future<DashboardStats> load({DateTime? now}) async {
    final at = now ?? DateTime.now();

    final totals = await db.customSelect(
      '''
SELECT
  (SELECT COUNT(*) FROM projects) AS projects,
  COUNT(*) AS total,
  COALESCE(SUM(status = 'done'), 0) AS done,
  COALESCE(SUM(status IN ('todo','inProgress')), 0) AS open,
  COALESCE(SUM(status IN ('todo','inProgress')
               AND deadline IS NOT NULL AND deadline < ?), 0) AS overdue
FROM tasks WHERE deleted_at IS NULL
''',
      variables: [Variable.withDateTime(at)],
      readsFrom: {db.tasks, db.projects},
    ).getSingle();

    final prio = await db.customSelect(
      'SELECT priority, COUNT(*) AS c FROM tasks '
      'WHERE deleted_at IS NULL GROUP BY priority',
      readsFrom: {db.tasks},
    ).get();
    final byPriority = {for (final p in TaskPriority.values) p: 0};
    for (final r in prio) {
      byPriority[TaskPriority.values.byName(r.read<String>('priority'))] =
          r.read<int>('c');
    }

    final assignees = await db.customSelect(
      '''
SELECT u.id AS id, u.name AS name, COUNT(t.id) AS c
FROM users u JOIN tasks t ON t.assignee_id = u.id AND t.deleted_at IS NULL
GROUP BY u.id ORDER BY c DESC, u.name LIMIT 50
''',
      readsFrom: {db.tasks, db.users},
    ).get();

    return DashboardStats(
      projects: totals.read<int>('projects'),
      totalTasks: totals.read<int>('total'),
      doneTasks: totals.read<int>('done'),
      openTasks: totals.read<int>('open'),
      overdueTasks: totals.read<int>('overdue'),
      byPriority: byPriority,
      byAssignee: assignees
          .map((r) => AssigneeCount(
              r.read<int>('id'), r.read<String>('name'), r.read<int>('c')))
          .toList(),
      projectProgress: await projects.getSummaries(),
    );
  }

  /// Реактивная статистика: пересчёт при любом изменении связанных таблиц.
  Stream<DashboardStats> watch() async* {
    yield await load();
    await for (final _ in db.tableUpdates(
        TableUpdateQuery.onAllTables([db.tasks, db.projects, db.users]))) {
      yield await load();
    }
  }
}
