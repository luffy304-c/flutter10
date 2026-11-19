import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/models/app_exception.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/repositories/attachment_repository.dart';
import 'package:taskflow/repositories/comment_repository.dart';
import 'package:taskflow/repositories/project_repository.dart';
import 'package:taskflow/repositories/stats_repository.dart';
import 'package:taskflow/repositories/task_repository.dart';
import 'package:taskflow/repositories/user_repository.dart';
import 'package:taskflow/services/benchmark_service.dart';

late AppDatabase db;
late UserRepository users;
late ProjectRepository projects;
late TaskRepository tasks;
late CommentRepository comments;
late StatsRepository stats;

/// Создаёт проект с двумя участниками: возвращает (projectId, anna, ivan).
Future<({int project, int anna, int ivan})> basicProject() async {
  final anna = await users.create(name: 'Анна', email: 'anna@test.io');
  final ivan = await users.create(name: 'Иван', email: 'ivan@test.io');
  final p = await projects.create(name: 'Проект');
  await projects.addMember(p, anna, role: MemberRole.owner);
  await projects.addMember(p, ivan);
  return (project: p, anna: anna, ivan: ivan);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
    db = AppDatabase.inMemory();
    users = UserRepository(db);
    projects = ProjectRepository(db);
    tasks = TaskRepository(db);
    comments = CommentRepository(db);
    stats = StatsRepository(db, projects);
  });
  tearDown(() => db.close());

  group('Пользователи', () {
    test('создание и удаление пользователя', () async {
      final id = await users.create(name: 'Анна', email: 'Anna@Test.io');
      final u = await users.getById(id);
      expect(u!.name, 'Анна');
      expect(u.email, 'anna@test.io'); // нормализация
      await users.delete(id);
      expect(await users.getById(id), isNull);
    });

    test('email должен быть уникальным', () async {
      await users.create(name: 'A', email: 'dup@test.io');
      expect(() => users.create(name: 'B', email: 'DUP@test.io'),
          throwsA(isA<AppException>()));
      // и на уровне самой БД (UNIQUE constraint)
      expect(
        () => db.into(db.users).insert(UsersCompanion.insert(
            name: 'X', email: 'dup@test.io', registeredAt: DateTime.now())),
        throwsA(anything),
      );
      expect(() => users.create(name: 'B', email: 'не-email'),
          throwsA(isA<AppException>()));
    });

    test('нельзя удалить пользователя с незавершёнными задачами', () async {
      final b = await basicProject();
      final t = await tasks.createTask(
          title: 'T', projectId: b.project, assigneeId: b.ivan, actorId: b.anna);
      expect(() => users.delete(b.ivan), throwsA(isA<AppException>()));
      await tasks.changeStatus(t, TaskStatus.done, actorId: b.anna);
      await users.delete(b.ivan); // теперь можно
      expect(await users.getById(b.ivan), isNull);
      // задача сохранилась, исполнитель обнулён (SET NULL)
      expect((await tasks.getById(t))!.assigneeId, isNull);
    });
  });

  group('Проекты', () {
    test('создание проекта и добавление участников / ролей', () async {
      final b = await basicProject();
      final members = await projects.getMembers(b.project);
      expect(members.length, 2);
      expect(members.first.member.role, MemberRole.owner);
      await projects.setRole(members.last.member.id, MemberRole.admin);
      expect((await projects.getMembers(b.project)).map((m) => m.member.role),
          containsAll([MemberRole.owner, MemberRole.admin]));
    });

    test('нельзя удалить или понизить единственного Owner', () async {
      final b = await basicProject(); // anna — единственный owner
      await expectLater(projects.removeMember(b.project, b.anna),
          throwsA(isA<AppException>()));
      final owner = (await projects.getMembers(b.project))
          .firstWhere((m) => m.user.id == b.anna);
      await expectLater(projects.setRole(owner.member.id, MemberRole.member),
          throwsA(isA<AppException>()));
      // после назначения второго Owner — можно
      final ivan = (await projects.getMembers(b.project))
          .firstWhere((m) => m.user.id == b.ivan);
      await projects.setRole(ivan.member.id, MemberRole.owner);
      await projects.removeMember(b.project, b.anna);
    });

    test('повторное добавление пользователя в проект запрещено', () async {
      final b = await basicProject();
      expect(() => projects.addMember(b.project, b.anna),
          throwsA(isA<AppException>()));
      expect(
        () => db.into(db.projectMembers).insert(ProjectMembersCompanion.insert(
            projectId: b.project, userId: b.anna)),
        throwsA(anything),
      ); // UNIQUE(project_id, user_id)
    });

    test('удаление проекта каскадно удаляет задачи и участников', () async {
      final b = await basicProject();
      final t = await tasks.createTask(title: 'T', projectId: b.project);
      await projects.delete(b.project);
      expect(await tasks.getById(t), isNull);
      expect((await db.select(db.projectMembers).get()), isEmpty);
      expect((await db.select(db.taskHistory).get()), isEmpty);
    });
  });

  group('Задачи', () {
    test('создание задачи пишет первую запись истории', () async {
      final b = await basicProject();
      final id = await tasks.createTask(
          title: 'Первая', projectId: b.project, assigneeId: b.anna, actorId: b.anna);
      final h = await tasks.getHistory(id);
      expect(h.length, 1);
      expect(h.single.entry.kind, HistoryKind.created);
      expect(h.single.entry.newStatus, TaskStatus.todo);
      expect(h.single.entry.oldStatus, isNull);
      expect((await tasks.getById(id))!.priority, TaskPriority.medium);
    });

    test('исполнитель должен быть участником проекта', () async {
      final b = await basicProject();
      final stranger = await users.create(name: 'Чужой', email: 'x@test.io');
      expect(
          () => tasks.createTask(
              title: 'T', projectId: b.project, assigneeId: stranger),
          throwsA(isA<AppException>()));
      final id = await tasks.createTask(title: 'T', projectId: b.project);
      expect(() => tasks.reassign(id, stranger), throwsA(isA<AppException>()));
    });

    test('нельзя создать задачу без проекта', () async {
      expect(() => tasks.createTask(title: 'T', projectId: null),
          throwsA(isA<AppException>()));
      expect(() => tasks.createTask(title: 'T', projectId: 999),
          throwsA(isA<AppException>()));
      // защита на уровне БД: внешний ключ
      expect(
        () => db.into(db.tasks).insert(TasksCompanion.insert(
            title: 'x',
            projectId: 12345,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now())),
        throwsA(anything),
      );
    });

    test('смена статуса сохраняет историю (старый/новый/кто/когда)', () async {
      final b = await basicProject();
      final id = await tasks.createTask(
          title: 'T', projectId: b.project, actorId: b.anna);
      await tasks.changeStatus(id, TaskStatus.inProgress, actorId: b.ivan);
      await tasks.changeStatus(id, TaskStatus.done, actorId: b.anna);
      final h = await tasks.getHistory(id); // новые сверху
      expect(h.length, 3);
      expect(h[0].entry.oldStatus, TaskStatus.inProgress);
      expect(h[0].entry.newStatus, TaskStatus.done);
      expect(h[1].entry.oldStatus, TaskStatus.todo);
      expect(h[1].entry.newStatus, TaskStatus.inProgress);
      expect(h[1].userName, 'Иван');
      expect(h[1].entry.changedAt, isNotNull);
      expect((await tasks.getById(id))!.status, TaskStatus.done);
    });

    test('транзакция: ошибка записи истории откатывает создание задачи',
        () async {
      final b = await basicProject();
      // actorId = 9999 нарушает FK task_history.changed_by -> история не пишется
      await expectLater(
        tasks.createTask(title: 'Откат', projectId: b.project, actorId: 9999),
        throwsA(anything),
      );
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.taskHistory).get(), isEmpty);
    });

    test('переназначение атомарно: проверка, смена и история', () async {
      final b = await basicProject();
      final stranger = await users.create(name: 'Чужой', email: 'x@test.io');
      final id = await tasks.createTask(
          title: 'T', projectId: b.project, assigneeId: b.anna, actorId: b.anna);
      await expectLater(tasks.reassign(id, stranger, actorId: b.anna),
          throwsA(isA<AppException>()));
      expect((await tasks.getById(id))!.assigneeId, b.anna);
      expect((await tasks.getHistory(id)).length, 1); // ничего не записано

      await tasks.reassign(id, b.ivan, actorId: b.anna);
      expect((await tasks.getById(id))!.assigneeId, b.ivan);
      final h = await tasks.getHistory(id);
      expect(h.first.entry.kind, HistoryKind.reassign);
      expect(h.first.entry.details, contains('Анна'));
      expect(h.first.entry.details, contains('Иван'));
    });

    test('Undo возвращает предыдущий статус и не откатывает дважды одно и то же',
        () async {
      final b = await basicProject();
      final id = await tasks.createTask(
          title: 'T', projectId: b.project, actorId: b.anna);
      await tasks.changeStatus(id, TaskStatus.inProgress, actorId: b.anna);
      await tasks.changeStatus(id, TaskStatus.done, actorId: b.anna);
      await tasks.undoLastStatusChange(id, actorId: b.anna);
      expect((await tasks.getById(id))!.status, TaskStatus.inProgress);
      await tasks.undoLastStatusChange(id, actorId: b.anna);
      expect((await tasks.getById(id))!.status, TaskStatus.todo);
      expect(() => tasks.undoLastStatusChange(id), throwsA(isA<AppException>()));
      expect((await tasks.getHistory(id)).length, 5); // история не теряется
    });

    test('лимит: не более 3 незавершённых задач на дедлайн-день', () async {
      final b = await basicProject();
      final day = DateTime(2030, 5, 20, 12);
      for (var i = 0; i < 3; i++) {
        await tasks.createTask(
            title: 'T$i',
            projectId: b.project,
            assigneeId: b.anna,
            deadline: day.add(Duration(hours: i)));
      }
      await expectLater(
          tasks.createTask(
              title: 'Четвёртая',
              projectId: b.project,
              assigneeId: b.anna,
              deadline: DateTime(2030, 5, 20, 23)),
          throwsA(isA<AppException>()));
      // другой день и другой исполнитель — можно
      await tasks.createTask(
          title: 'ok1',
          projectId: b.project,
          assigneeId: b.anna,
          deadline: DateTime(2030, 5, 21));
      final t4 = await tasks.createTask(
          title: 'ok2', projectId: b.project, assigneeId: b.ivan, deadline: day);
      // переназначение на Анну тоже упирается в лимит
      await expectLater(
          tasks.reassign(t4, b.anna), throwsA(isA<AppException>()));
    });
  });

  group('Комментарии', () {
    test('добавление, проверка задачи и удаление только автором', () async {
      final b = await basicProject();
      final id = await tasks.createTask(title: 'T', projectId: b.project);
      final c = await comments.add(taskId: id, authorId: b.anna, text: ' Привет ');
      final list = await comments.getForTask(id);
      expect(list.single.comment.body, 'Привет');
      expect(list.single.authorName, 'Анна');

      await expectLater(comments.add(taskId: 777, authorId: b.anna, text: 'x'),
          throwsA(isA<AppException>()));
      await expectLater(comments.delete(c, requesterId: b.ivan),
          throwsA(isA<AppException>()));
      await comments.delete(c, requesterId: b.anna);
      expect(await comments.getForTask(id), isEmpty);
    });

    test('вложения хранят путь, а не содержимое', () async {
      final b = await basicProject();
      final id = await tasks.createTask(title: 'T', projectId: b.project);
      final repo = AttachmentRepository(db);
      await repo.add(taskId: id, fileName: 'a.pdf', filePath: '/docs/a.pdf');
      final rows = await repo.watchForTask(id).first;
      expect(rows.single.filePath, '/docs/a.pdf');
      expect(rows.single.fileName, 'a.pdf');
    });
  });

  group('Корзина', () {
    test('soft delete скрывает задачу, restore возвращает, purge удаляет',
        () async {
      final b = await basicProject();
      final id = await tasks.createTask(title: 'Корзина', projectId: b.project);
      await tasks.softDelete(id);

      final row = await tasks.getById(id);
      expect(row, isNotNull); // физически осталась
      expect(row!.deletedAt, isNotNull);
      expect(await tasks.count(const TaskFilter()), 0);
      expect(await tasks.count(const TaskFilter(onlyDeleted: true)), 1);
      expect((await stats.load()).totalTasks, 0); // не в статистике
      // нельзя полностью удалить, минуя корзину
      await tasks.restore(id);
      expect(await tasks.count(const TaskFilter()), 1);
      await expectLater(tasks.purge(id), throwsA(isA<AppException>()));

      await tasks.softDelete(id);
      await tasks.purge(id);
      expect(await tasks.getById(id), isNull);
      expect(await db.select(db.taskHistory).get(), isEmpty); // каскад
    });
  });

  group('Статистика, фильтры, поиск', () {
    test('статистика считается корректно', () async {
      final b = await basicProject();
      final now = DateTime(2030, 1, 10, 12);
      Future<int> mk(String t, TaskStatus s, TaskPriority p, int? who,
              DateTime? d) =>
          tasks.createTask(
              title: t,
              projectId: b.project,
              status: s,
              priority: p,
              assigneeId: who,
              deadline: d);
      await mk('a', TaskStatus.todo, TaskPriority.low, b.anna, DateTime(2030, 1, 1));
      await mk('b', TaskStatus.inProgress, TaskPriority.high, b.anna, DateTime(2030, 2, 1));
      await mk('c', TaskStatus.done, TaskPriority.high, b.ivan, DateTime(2030, 1, 1));
      await mk('d', TaskStatus.cancelled, TaskPriority.critical, null, null);
      final deleted = await mk('e', TaskStatus.todo, TaskPriority.low, null, null);
      await tasks.softDelete(deleted);
      await projects.create(name: 'Пустой');

      final s = await stats.load(now: now);
      expect(s.projects, 2);
      expect(s.totalTasks, 4);
      expect(s.doneTasks, 1);
      expect(s.openTasks, 2);
      expect(s.overdueTasks, 1); // только 'a': done с прошлым дедлайном не в счёт
      expect(s.byPriority[TaskPriority.high], 2);
      expect(s.byPriority[TaskPriority.low], 1);
      expect(s.byPriority[TaskPriority.critical], 1);
      expect(s.byPriority[TaskPriority.medium], 0);
      expect(s.byAssignee.firstWhere((a) => a.name == 'Анна').count, 2);
      final prog =
          s.projectProgress.firstWhere((p) => p.project.id == b.project);
      expect(prog.percent, closeTo(100 / 3, 0.01)); // 1 из 3 (без cancelled)
      expect(s.projectProgress.firstWhere((p) => p.project.name == 'Пустой').percent, 0);
    });

    test('фильтрация, сортировка и поиск (в т.ч. кириллица без учёта регистра)',
        () async {
      final b = await basicProject();
      await tasks.createTask(
          title: 'Написать Отчёт',
          description: 'за квартал',
          projectId: b.project,
          assigneeId: b.anna,
          priority: TaskPriority.high,
          deadline: DateTime(2030, 3, 3));
      await tasks.createTask(
          title: 'Сверстать экран',
          description: 'ПОДГОТОВИТЬ отчёт для клиента',
          projectId: b.project,
          assigneeId: b.ivan,
          deadline: DateTime(2030, 3, 1));
      await tasks.createTask(title: 'Без дедлайна', projectId: b.project);

      Future<List<String>> titles(TaskFilter f) async =>
          (await tasks.getPage(f)).map((e) => e.task.title).toList();

      expect(await titles(const TaskFilter(search: 'отчёт')),
          hasLength(2)); // название + описание
      expect(await titles(const TaskFilter(search: 'ЭКРАН')), ['Сверстать экран']);
      expect(await titles(TaskFilter(priority: TaskPriority.high)),
          ['Написать Отчёт']);
      expect(await titles(TaskFilter(assigneeId: b.ivan)), ['Сверстать экран']);
      expect(await titles(TaskFilter(status: TaskStatus.done)), isEmpty);
      expect(
          await titles(const TaskFilter(
              sortField: TaskSortField.deadline, ascending: true)),
          ['Сверстать экран', 'Написать Отчёт', 'Без дедлайна']); // NULL в конце
    });

    test('пагинация limit/offset', () async {
      final b = await basicProject();
      for (var i = 0; i < 25; i++) {
        await tasks.createTask(title: 'Задача $i', projectId: b.project);
      }
      final p1 = await tasks.getPage(const TaskFilter(), limit: 10, offset: 0);
      final p3 = await tasks.getPage(const TaskFilter(), limit: 10, offset: 20);
      expect(p1.length, 10);
      expect(p3.length, 5);
      expect(p1.map((e) => e.task.id).toSet().intersection(p3.map((e) => e.task.id).toSet()),
          isEmpty);
      expect(await tasks.count(const TaskFilter()), 25);
    });

    test('watch(): список обновляется автоматически', () async {
      final b = await basicProject();
      final stream = tasks.watchTasks(const TaskFilter());
      final expectation = expectLater(
        stream.map((l) => l.length),
        emitsInOrder([0, 1, 2]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tasks.createTask(title: 'A', projectId: b.project);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tasks.createTask(title: 'B', projectId: b.project);
      await expectation;
    });
  });

  group('Миграции и индексы', () {
    test('миграция v1 -> v2 добавляет priority=medium, данные сохраняются',
        () async {
      // База версии 1: таблица tasks БЕЗ поля priority.
      final raw = sqlite.sqlite3.openInMemory();
      raw.execute('''
CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, registered_at INTEGER NOT NULL);
CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, finished_at INTEGER, status TEXT NOT NULL DEFAULT 'active');
CREATE TABLE project_members (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, role TEXT NOT NULL DEFAULT 'member', UNIQUE(project_id, user_id));
CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE, assignee_id INTEGER REFERENCES users(id) ON DELETE SET NULL, status TEXT NOT NULL DEFAULT 'todo', deadline INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER);
CREATE TABLE comments (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, body TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE attachments (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, file_name TEXT NOT NULL, file_path TEXT NOT NULL, added_at INTEGER NOT NULL);
CREATE TABLE task_history (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, kind TEXT NOT NULL, old_status TEXT, new_status TEXT NOT NULL, details TEXT, changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL, changed_at INTEGER NOT NULL, undone INTEGER NOT NULL DEFAULT 0);
INSERT INTO users VALUES (1, 'Анна', 'anna@old.io', 1700000000);
INSERT INTO projects VALUES (1, 'Старый проект', 'описание', 1700000000, NULL, 'active');
INSERT INTO tasks (id, title, project_id, assignee_id, status, deadline, created_at, updated_at) VALUES (1, 'Старая 1', 1, 1, 'inProgress', 1800000000, 1700000000, 1700000000);
INSERT INTO tasks (id, title, project_id, status, created_at, updated_at) VALUES (2, 'Старая 2', 1, 'done', 1700000000, 1700000000);
PRAGMA user_version = 1;
''');
      final old = raw.select('PRAGMA table_info(tasks)').map((r) => r['name']);
      expect(old, isNot(contains('priority')));

      final migrated = AppDatabase(NativeDatabase.opened(raw));
      addTearDown(migrated.close);
      final rows = await (migrated.select(migrated.tasks)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(rows.length, 2); // данные не потеряны
      expect(rows.map((t) => t.title), ['Старая 1', 'Старая 2']);
      expect(rows.map((t) => t.priority), everyElement(TaskPriority.medium));
      expect(rows[0].status, TaskStatus.inProgress);
      expect(rows[0].assigneeId, 1);
      expect(rows[0].deadline, isNotNull);
      final cols = await migrated
          .customSelect('PRAGMA table_info(tasks)')
          .get()
          .then((r) => r.map((e) => e.read<String>('name')));
      expect(cols, contains('priority'));
      final version = await migrated.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);

      // после миграции приложение работает как обычно
      final repo = TaskRepository(migrated);
      final id = await repo.createTask(
          title: 'Новая', projectId: 1, priority: TaskPriority.critical);
      expect((await repo.getById(id))!.priority, TaskPriority.critical);
      expect(await BenchmarkService(migrated).existingTaskIndexes(),
          contains('idx_tasks_priority'));
    });

    test('индексы созданы; тестовый набор данных и сравнение работают', () async {
      final bench = BenchmarkService(db);
      expect(await bench.existingTaskIndexes(),
          containsAll(BenchmarkService.taskIndexes.keys));

      await bench.seed(users: 40, projects: 5, tasks: 400);
      expect((await db.select(db.users).get()).length, 40);
      expect((await db.select(db.projects).get()).length, 5);
      expect(await tasks.count(const TaskFilter()), 400);

      final results = await bench.run(repeats: 1);
      expect(results, isNotEmpty);
      expect(results.every((r) => r.withIndexMs >= 0 && r.withoutIndexMs >= 0), isTrue);
      // индексы восстановлены после сравнения
      expect(await bench.existingTaskIndexes(),
          containsAll(BenchmarkService.taskIndexes.keys));
    });
  });
}
