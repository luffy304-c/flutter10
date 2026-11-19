import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/app_exception.dart';
import '../models/enums.dart';
import '../models/views.dart';

/// Максимум незавершённых задач у исполнителя с одним и тем же днём дедлайна.
const maxOpenTasksPerDeadlineDay = 3;

class TaskRepository {
  TaskRepository(this.db);
  final AppDatabase db;

  // ------------------------------------------------------------------ запросы

  Expression<bool> _where(TaskFilter f) {
    final t = db.tasks;
    Expression<bool> w =
        f.onlyDeleted ? t.deletedAt.isNotNull() : t.deletedAt.isNull();
    if (f.projectId != null) w = w & t.projectId.equals(f.projectId!);
    if (f.assigneeId != null) w = w & t.assigneeId.equals(f.assigneeId!);
    if (f.status != null) w = w & t.status.equalsValue(f.status!);
    if (f.priority != null) w = w & t.priority.equalsValue(f.priority!);
    final s = f.search.trim().toLowerCase();
    if (s.isNotEmpty) {
      final pattern = '%${s.replaceAll('%', '').replaceAll('_', '')}%';
      final title = CustomExpression<String>('ulower("tasks"."title")');
      final desc = CustomExpression<String>('ulower("tasks"."description")');
      w = w & (title.like(pattern) | desc.like(pattern));
    }
    return w;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _query(TaskFilter f,
      {int? limit, int offset = 0}) {
    final t = db.tasks;
    final q = db.select(t).join([
      innerJoin(db.projects, db.projects.id.equalsExp(t.projectId)),
      leftOuterJoin(db.users, db.users.id.equalsExp(t.assigneeId)),
    ])
      ..where(_where(f));
    final mode = f.ascending ? OrderingMode.asc : OrderingMode.desc;
    if (f.onlyDeleted) {
      q.orderBy([OrderingTerm(expression: t.deletedAt, mode: OrderingMode.desc)]);
    } else if (f.sortField == TaskSortField.deadline) {
      q.orderBy([
        OrderingTerm(expression: t.deadline, mode: mode, nulls: NullsOrder.last),
        OrderingTerm.asc(t.id),
      ]);
    } else {
      q.orderBy([
        OrderingTerm(expression: t.createdAt, mode: mode),
        OrderingTerm(expression: t.id, mode: mode),
      ]);
    }
    if (limit != null) q.limit(limit, offset: offset);
    return q;
  }

  TaskView _map(TypedResult r) => TaskView(
        task: r.readTable(db.tasks),
        projectName: r.read(db.projects.name)!,
        assigneeName: r.read(db.users.name),
      );

  /// Реактивный список (первые [limit] записей) — для пагинации «подгрузить ещё».
  Stream<List<TaskView>> watchTasks(TaskFilter f, {int limit = 50}) =>
      _query(f, limit: limit).watch().map((rows) => rows.map(_map).toList());

  /// Постраничная выборка (limit/offset).
  Future<List<TaskView>> getPage(TaskFilter f,
          {int limit = 50, int offset = 0}) async =>
      (await _query(f, limit: limit, offset: offset).get()).map(_map).toList();

  Stream<int> watchCount(TaskFilter f) {
    final t = db.tasks;
    final c = t.id.count();
    return (db.selectOnly(t)
          ..addColumns([c])
          ..where(_where(f)))
        .map((r) => r.read(c)!)
        .watchSingle();
  }

  Future<int> count(TaskFilter f) => watchCount(f).first;

  Future<Task?> getById(int id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<TaskView?> watchTask(int id) {
    final q = db.select(db.tasks).join([
      innerJoin(db.projects, db.projects.id.equalsExp(db.tasks.projectId)),
      leftOuterJoin(db.users, db.users.id.equalsExp(db.tasks.assigneeId)),
    ])
      ..where(db.tasks.id.equals(id));
    return q.watch().map((rows) => rows.isEmpty ? null : _map(rows.first));
  }

  // ----------------------------------------------------------------- проверки

  Future<bool> _isMember(int projectId, int userId) async {
    final m = db.projectMembers;
    final c = m.id.count();
    final n = await (db.selectOnly(m)
          ..addColumns([c])
          ..where(m.projectId.equals(projectId) & m.userId.equals(userId)))
        .map((r) => r.read(c)!)
        .getSingle();
    return n > 0;
  }

  /// Задание 3: у исполнителя не больше трёх незавершённых задач на один день
  /// дедлайна. Проверка — SQL-запрос COUNT к БД.
  Future<int> countOpenTasksOnDay(int assigneeId, DateTime day,
      {int? excludeTaskId}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final t = db.tasks;
    final c = t.id.count();
    final q = db.selectOnly(t)
      ..addColumns([c])
      ..where(t.assigneeId.equals(assigneeId) &
          t.deletedAt.isNull() &
          t.status.isIn([TaskStatus.todo.name, TaskStatus.inProgress.name]) &
          t.deadline.isBiggerOrEqualValue(start) &
          t.deadline.isSmallerThanValue(end));
    if (excludeTaskId != null) q.where(t.id.equals(excludeTaskId).not());
    return q.map((r) => r.read(c)!).getSingle();
  }

  Future<void> _checkDailyLimit(int? assigneeId, DateTime? deadline,
      {int? excludeTaskId}) async {
    if (assigneeId == null || deadline == null) return;
    final n =
        await countOpenTasksOnDay(assigneeId, deadline, excludeTaskId: excludeTaskId);
    if (n >= maxOpenTasksPerDeadlineDay) {
      throw AppException(
          'У исполнителя уже $n незавершённые задачи с дедлайном на эту дату (максимум $maxOpenTasksPerDeadlineDay)');
    }
  }

  Future<void> _checkAssignee(int projectId, int? assigneeId) async {
    if (assigneeId == null) return;
    if (!await _isMember(projectId, assigneeId)) {
      throw AppException('Исполнитель должен быть участником проекта');
    }
  }

  Future<void> _addHistory({
    required int taskId,
    required HistoryKind kind,
    TaskStatus? oldStatus,
    required TaskStatus newStatus,
    int? actorId,
    String? details,
  }) async {
    await db.into(db.taskHistory).insert(TaskHistoryCompanion.insert(
          taskId: taskId,
          kind: kind,
          oldStatus: Value(oldStatus),
          newStatus: newStatus,
          details: Value(details),
          changedBy: Value(actorId),
          changedAt: DateTime.now(),
        ));
  }

  Future<Task> _requireActive(int id) async {
    final t = await getById(id);
    if (t == null || t.deletedAt != null) throw AppException('Задача не найдена');
    return t;
  }

  Future<String> _userName(int? id) async {
    if (id == null) return 'не назначен';
    final u = await (db.select(db.users)..where((u) => u.id.equals(id)))
        .getSingleOrNull();
    return u?.name ?? '#$id';
  }

  // ---------------------------------------------------------------- операции

  /// Создание задачи + первая запись истории — в одной транзакции.
  /// Любая ошибка при записи истории откатывает и сохранение задачи.
  Future<int> createTask({
    required String title,
    String description = '',
    required int? projectId,
    int? assigneeId,
    TaskPriority priority = TaskPriority.medium,
    TaskStatus status = TaskStatus.todo,
    DateTime? deadline,
    int? actorId,
  }) async {
    if (projectId == null) {
      throw AppException('Задача должна принадлежать проекту');
    }
    if (title.trim().isEmpty) throw AppException('Введите название задачи');
    return db.transaction(() async {
      final project = await (db.select(db.projects)
            ..where((p) => p.id.equals(projectId)))
          .getSingleOrNull();
      if (project == null) throw AppException('Проект не найден');
      await _checkAssignee(projectId, assigneeId);
      if (status.isOpen) await _checkDailyLimit(assigneeId, deadline);
      final now = DateTime.now();
      final id = await db.into(db.tasks).insert(TasksCompanion.insert(
            title: title.trim(),
            description: Value(description.trim()),
            projectId: projectId,
            assigneeId: Value(assigneeId),
            priority: Value(priority),
            status: Value(status),
            deadline: Value(deadline),
            createdAt: now,
            updatedAt: now,
          ));
      await _addHistory(
        taskId: id,
        kind: HistoryKind.created,
        newStatus: status,
        actorId: actorId,
        details: 'Задача создана',
      );
      return id;
    });
  }

  /// Редактирование полей (название, описание, дедлайн, приоритет).
  Future<void> updateTask(
    int id, {
    required String title,
    required String description,
    required TaskPriority priority,
    DateTime? deadline,
  }) async {
    if (title.trim().isEmpty) throw AppException('Введите название задачи');
    await db.transaction(() async {
      final task = await _requireActive(id);
      if (task.status.isOpen && deadline != task.deadline) {
        await _checkDailyLimit(task.assigneeId, deadline, excludeTaskId: id);
      }
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          title: Value(title.trim()),
          description: Value(description.trim()),
          priority: Value(priority),
          deadline: Value(deadline),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> changePriority(int id, TaskPriority priority) async {
    await _requireActive(id);
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(priority: Value(priority), updatedAt: Value(DateTime.now())),
    );
  }

  /// Смена статуса + запись истории (атомарно).
  Future<void> changeStatus(int id, TaskStatus newStatus, {int? actorId}) async {
    await db.transaction(() async {
      final task = await _requireActive(id);
      if (task.status == newStatus) return;
      if (newStatus.isOpen && !task.status.isOpen) {
        await _checkDailyLimit(task.assigneeId, task.deadline, excludeTaskId: id);
      }
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(status: Value(newStatus), updatedAt: Value(DateTime.now())),
      );
      await _addHistory(
        taskId: id,
        kind: HistoryKind.status,
        oldStatus: task.status,
        newStatus: newStatus,
        actorId: actorId,
      );
    });
  }

  /// Назначение / переназначение исполнителя: проверка участия в проекте,
  /// проверка лимита, обновление и запись в историю — в одной транзакции.
  Future<void> reassign(int id, int? newAssigneeId, {int? actorId}) async {
    await db.transaction(() async {
      final task = await _requireActive(id);
      if (task.assigneeId == newAssigneeId) return;
      await _checkAssignee(task.projectId, newAssigneeId);
      if (task.status.isOpen) {
        await _checkDailyLimit(newAssigneeId, task.deadline, excludeTaskId: id);
      }
      final oldName = await _userName(task.assigneeId);
      final newName = await _userName(newAssigneeId);
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          assigneeId: Value(newAssigneeId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _addHistory(
        taskId: id,
        kind: HistoryKind.reassign,
        oldStatus: task.status,
        newStatus: task.status,
        actorId: actorId,
        details: 'Исполнитель: $oldName → $newName',
      );
    });
  }

  // --------------------------------------------------------------------- Undo

  /// Последнее ещё не отменённое изменение статуса (для кнопки Undo).
  Stream<TaskHistoryEntry?> watchUndoable(int taskId) => (db.select(db.taskHistory)
        ..where((h) =>
            h.taskId.equals(taskId) &
            h.kind.equalsValue(HistoryKind.status) &
            h.undone.equals(false))
        ..orderBy([(h) => OrderingTerm.desc(h.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<TaskHistoryEntry?> _lastUndoable(int taskId) => (db.select(db.taskHistory)
        ..where((h) =>
            h.taskId.equals(taskId) &
            h.kind.equalsValue(HistoryKind.status) &
            h.undone.equals(false))
        ..orderBy([(h) => OrderingTerm.desc(h.id)])
        ..limit(1))
      .getSingleOrNull();

  /// Задание 2: возвращает предыдущий статус и фиксирует это в истории.
  Future<void> undoLastStatusChange(int taskId, {int? actorId}) async {
    await db.transaction(() async {
      final task = await _requireActive(taskId);
      final last = await _lastUndoable(taskId);
      if (last == null || last.oldStatus == null) {
        throw AppException('Нет изменений статуса для отмены');
      }
      final target = last.oldStatus!;
      if (target.isOpen && !task.status.isOpen) {
        await _checkDailyLimit(task.assigneeId, task.deadline, excludeTaskId: taskId);
      }
      await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(status: Value(target), updatedAt: Value(DateTime.now())),
      );
      await (db.update(db.taskHistory)..where((h) => h.id.equals(last.id)))
          .write(const TaskHistoryCompanion(undone: Value(true)));
      await _addHistory(
        taskId: taskId,
        kind: HistoryKind.undo,
        oldStatus: task.status,
        newStatus: target,
        actorId: actorId,
        details: 'Отмена изменения статуса',
      );
    });
  }

  // ------------------------------------------------------------------ корзина

  /// Soft delete: задача остаётся в БД, заполняется deletedAt.
  Future<void> softDelete(int id) async {
    await _requireActive(id);
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  Future<void> restore(int id) async {
    final t = await getById(id);
    if (t == null || t.deletedAt == null) {
      throw AppException('Задача не найдена в корзине');
    }
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Полное удаление — только для задач из корзины.
  Future<void> purge(int id) async {
    final t = await getById(id);
    if (t == null) return;
    if (t.deletedAt == null) {
      throw AppException('Сначала переместите задачу в корзину');
    }
    await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> emptyTrash() =>
      (db.delete(db.tasks)..where((t) => t.deletedAt.isNotNull())).go();

  // ------------------------------------------------------------------ история

  Stream<List<HistoryView>> watchHistory(int taskId) {
    final h = db.taskHistory;
    final q = db.select(h).join([
      leftOuterJoin(db.users, db.users.id.equalsExp(h.changedBy)),
    ])
      ..where(h.taskId.equals(taskId))
      ..orderBy([OrderingTerm.desc(h.id)]);
    return q.watch().map((rows) => rows
        .map((r) => HistoryView(
            entry: r.readTable(h), userName: r.read(db.users.name)))
        .toList());
  }

  Future<List<HistoryView>> getHistory(int taskId) => watchHistory(taskId).first;
}
