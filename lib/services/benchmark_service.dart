import 'dart:math';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/project_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/task_repository.dart';

class BenchResult {
  const BenchResult(this.name, this.withIndexMs, this.withoutIndexMs);
  final String name;
  final double withIndexMs;
  final double withoutIndexMs;
  double get speedup => withIndexMs == 0 ? 0 : withoutIndexMs / withIndexMs;
}

/// Генерация тестовой БД и сравнение скорости запросов с индексами и без них.
class BenchmarkService {
  BenchmarkService(this.db);
  final AppDatabase db;

  /// Индексы таблицы tasks, которые включаются / отключаются при сравнении.
  static const taskIndexes = <String, String>{
    'idx_tasks_project': 'tasks(project_id)',
    'idx_tasks_assignee': 'tasks(assignee_id)',
    'idx_tasks_status': 'tasks(status)',
    'idx_tasks_priority': 'tasks(priority)',
    'idx_tasks_deadline': 'tasks(deadline)',
    'idx_tasks_created_at': 'tasks(created_at)',
    'idx_tasks_deleted_at': 'tasks(deleted_at)',
  };

  static const _words = [
    'отчёт', 'релиз', 'дизайн', 'тест', 'баг', 'интеграция', 'миграция',
    'документация', 'API', 'экран', 'оптимизация', 'ревью', 'деплой',
    'аналитика', 'backend', 'frontend', 'бюджет', 'встреча', 'план', 'аудит',
  ];

  /// Целевой объём данных по заданию.
  static const targetUsers = 1000;
  static const targetProjects = 100;
  static const targetTasks = 10000;

  /// Добивает основную БД до 1000 пользователей / 100 проектов / 10 000 задач
  /// (учитывая уже существующие записи). Ничего не делает, если данных хватает.
  Future<void> ensureTargetScale({void Function(String stage)? onProgress}) async {
    Future<int> count(String t) async =>
        (await db.customSelect('SELECT COUNT(*) AS c FROM $t').getSingle()).read<int>('c');
    final u = max(0, targetUsers - await count('users'));
    final p = max(0, targetProjects - await count('projects'));
    final t = max(0, targetTasks - await count('tasks'));
    if (u == 0 && p == 0 && t == 0) return;
    await seed(users: u, projects: p, tasks: t, onProgress: onProgress);
  }

  /// Добавляет в БД [users] пользователей, [projects] проектов, [tasks] задач.
  /// Участники проектов создаются автоматически (по 30 на проект, первый — Owner),
  /// у каждой задачи есть запись «создана» в истории.
  Future<void> seed({
    int users = targetUsers,
    int projects = targetProjects,
    int tasks = targetTasks,
    int? randomSeed,
    void Function(String stage)? onProgress,
  }) async {
    final rnd = Random(randomSeed ?? 42);
    final now = DateTime.now();
    await db.transaction(() async {
      onProgress?.call('Пользователи…');
      final stamp = now.microsecondsSinceEpoch;
      final firstUser = (await db
              .customSelect('SELECT COALESCE(MAX(id),0) AS m FROM users')
              .getSingle())
          .read<int>('m');
      if (users > 0) {
        await db.batch((b) {
          b.insertAll(db.users, [
            for (var i = 0; i < users; i++)
              UsersCompanion.insert(
                name: 'Пользователь ${firstUser + i + 1}',
                email: 'u${stamp}_$i@bench.test',
                registeredAt: now.subtract(Duration(days: rnd.nextInt(700))),
              ),
          ]);
        });
      }
      final userIds = (await db.select(db.users).get()).map((u) => u.id).toList();

      onProgress?.call('Проекты…');
      final firstProject = (await db
              .customSelect('SELECT COALESCE(MAX(id),0) AS m FROM projects')
              .getSingle())
          .read<int>('m');
      if (projects > 0) {
        await db.batch((b) {
          b.insertAll(db.projects, [
            for (var i = 0; i < projects; i++)
              ProjectsCompanion.insert(
                name: 'Проект ${firstProject + i + 1} ${_words[rnd.nextInt(_words.length)]}',
                description: Value('Тестовый проект №${firstProject + i + 1}'),
                createdAt: now.subtract(Duration(days: rnd.nextInt(300))),
                status: Value(ProjectStatus.values[rnd.nextInt(3)]),
              ),
          ]);
        });
        onProgress?.call('Участники…');
        final newIds = (await (db.select(db.projects)
                  ..where((p) => p.id.isBiggerThanValue(firstProject)))
                .get())
            .map((p) => p.id);
        final memberRows = <ProjectMembersCompanion>[];
        for (final pid in newIds) {
          final pool = List<int>.from(userIds)..shuffle(rnd);
          final chosen = pool.take(min(30, pool.length)).toList();
          for (var i = 0; i < chosen.length; i++) {
            memberRows.add(ProjectMembersCompanion.insert(
              projectId: pid,
              userId: chosen[i],
              role: Value(i == 0
                  ? MemberRole.owner
                  : (i < 4 ? MemberRole.admin : MemberRole.member)),
            ));
          }
        }
        await db.batch((b) => b.insertAll(db.projectMembers, memberRows));
      }

      if (tasks > 0) {
        onProgress?.call('Задачи…');
        final projectIds = (await db.select(db.projects).get()).map((p) => p.id).toList();
        final membersOf = <int, List<int>>{};
        for (final m in await db.select(db.projectMembers).get()) {
          (membersOf[m.projectId] ??= []).add(m.userId);
        }
        final firstTask = (await db
                .customSelect('SELECT COALESCE(MAX(id),0) AS m FROM tasks')
                .getSingle())
            .read<int>('m');
        if (projectIds.isNotEmpty) {
          final rows = <TasksCompanion>[];
          for (var i = 0; i < tasks; i++) {
            final pid = projectIds[rnd.nextInt(projectIds.length)];
            final members = membersOf[pid] ?? const <int>[];
            final created = now.subtract(Duration(minutes: rnd.nextInt(60 * 24 * 120)));
            rows.add(TasksCompanion.insert(
              title: 'Задача ${firstTask + i + 1}: ${_words[rnd.nextInt(_words.length)]} '
                  '${_words[rnd.nextInt(_words.length)]}',
              description: Value('Описание ${_words[rnd.nextInt(_words.length)]} '
                  'для задачи ${firstTask + i + 1}'),
              projectId: pid,
              assigneeId: Value(members.isEmpty || rnd.nextInt(10) == 0
                  ? null
                  : members[rnd.nextInt(members.length)]),
              priority: Value(TaskPriority.values[rnd.nextInt(4)]),
              status: Value(TaskStatus.values[rnd.nextInt(4)]),
              deadline: Value(rnd.nextInt(6) == 0
                  ? null
                  : now.add(Duration(days: rnd.nextInt(120) - 40))),
              createdAt: created,
              updatedAt: created,
            ));
          }
          await db.batch((b) => b.insertAll(db.tasks, rows));
          // Первая запись истории для каждой новой задачи.
          await db.customStatement(
            "INSERT INTO task_history (task_id, kind, old_status, new_status, details, changed_by, changed_at, undone) "
            "SELECT id, 'created', NULL, status, 'Задача создана', assignee_id, created_at, 0 "
            "FROM tasks WHERE id > $firstTask",
          );
        }
      }
    });
    onProgress?.call('Готово');
  }

  Future<void> dropIndexes() async {
    for (final name in taskIndexes.keys) {
      await db.customStatement('DROP INDEX IF EXISTS $name');
    }
  }

  Future<void> createIndexes() async {
    for (final e in taskIndexes.entries) {
      await db.customStatement('CREATE INDEX IF NOT EXISTS ${e.key} ON ${e.value}');
    }
  }

  Future<List<String>> existingTaskIndexes() async => (await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index' "
              "AND tbl_name='tasks' AND name LIKE 'idx_%'")
          .get())
      .map((r) => r.read<String>('name'))
      .toList();

  /// Сценарии: поиск, фильтрация, сортировка, страница, статистика.
  Map<String, Future<void> Function()> _cases() {
    final tasks = TaskRepository(db);
    final stats = StatsRepository(db, ProjectRepository(db));
    return {
      'Поиск по названию/описанию (стр. 50)': () =>
          tasks.getPage(const TaskFilter(search: 'отчёт')),
      'Фильтр по проекту + сортировка по дедлайну': () => tasks.getPage(
          const TaskFilter(projectId: 50, sortField: TaskSortField.deadline, ascending: true)),
      'Фильтр по исполнителю': () => tasks.getPage(const TaskFilter(assigneeId: 500)),
      'Фильтр статус+приоритет, сортировка по созданию': () => tasks.getPage(
          TaskFilter(status: TaskStatus.inProgress, priority: TaskPriority.critical)),
      'Глубокая страница (offset 5000)': () =>
          tasks.getPage(const TaskFilter(), offset: 5000),
      'Подсчёт задач по фильтру': () =>
          tasks.count(TaskFilter(status: TaskStatus.done, priority: TaskPriority.high)),
      'Статистика Dashboard': () => stats.load(),
    };
  }

  Future<double> _time(Future<void> Function() fn, int repeats) async {
    await fn(); // прогрев
    final sw = Stopwatch()..start();
    for (var i = 0; i < repeats; i++) {
      await fn();
    }
    sw.stop();
    return sw.elapsedMicroseconds / 1000 / repeats;
  }

  /// Запускает все сценарии без индексов, затем с индексами.
  /// По окончании индексы всегда восстанавливаются.
  Future<List<BenchResult>> run({int repeats = 5}) async {
    final cases = _cases();
    final without = <String, double>{};
    final withIdx = <String, double>{};
    try {
      await dropIndexes();
      for (final e in cases.entries) {
        without[e.key] = await _time(e.value, repeats);
      }
    } finally {
      await createIndexes();
    }
    await db.customStatement('ANALYZE');
    for (final e in cases.entries) {
      withIdx[e.key] = await _time(e.value, repeats);
    }
    return [
      for (final k in cases.keys) BenchResult(k, withIdx[k]!, without[k]!),
    ];
  }
}
