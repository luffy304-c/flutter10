import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/app_exception.dart';
import '../models/enums.dart';
import '../models/views.dart';
import 'user_repository.dart' show isUniqueViolation;

class ProjectRepository {
  ProjectRepository(this.db);
  final AppDatabase db;

  static const _summarySql = '''
SELECT p.*,
  (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.deleted_at IS NULL) AS total_tasks,
  (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.deleted_at IS NULL AND t.status = 'done') AS done_tasks,
  (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.deleted_at IS NULL AND t.status <> 'cancelled') AS counted_tasks
FROM projects p
''';

  ProjectSummary _mapSummary(QueryRow r) => ProjectSummary(
        project: db.projects.map(r.data),
        totalTasks: r.read<int>('total_tasks'),
        doneTasks: r.read<int>('done_tasks'),
        countedTasks: r.read<int>('counted_tasks'),
      );

  /// Проекты с прогрессом, считаемым SQL-запросом.
  Stream<List<ProjectSummary>> watchSummaries() => db
      .customSelect('$_summarySql ORDER BY p.created_at DESC, p.id DESC',
          readsFrom: {db.projects, db.tasks})
      .watch()
      .map((rows) => rows.map(_mapSummary).toList());

  Future<List<ProjectSummary>> getSummaries() async => (await db
          .customSelect('$_summarySql ORDER BY p.created_at DESC, p.id DESC',
              readsFrom: {db.projects, db.tasks})
          .get())
      .map(_mapSummary)
      .toList();

  Stream<List<Project>> watchAll() => (db.select(db.projects)
        ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();

  Future<Project?> getById(int id) =>
      (db.select(db.projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<Project?> watchById(int id) =>
      (db.select(db.projects)..where((p) => p.id.equals(id))).watchSingleOrNull();

  void _validate(String name, DateTime createdAt, DateTime? finishedAt) {
    if (name.trim().isEmpty) throw AppException('Введите название проекта');
    if (finishedAt != null && finishedAt.isBefore(createdAt)) {
      throw AppException('Дата завершения не может быть раньше даты создания');
    }
  }

  Future<int> create({
    required String name,
    String description = '',
    ProjectStatus status = ProjectStatus.active,
    DateTime? finishedAt,
    DateTime? createdAt,
  }) async {
    final created = createdAt ?? DateTime.now();
    _validate(name, created, finishedAt);
    return db.into(db.projects).insert(ProjectsCompanion.insert(
          name: name.trim(),
          description: Value(description.trim()),
          createdAt: created,
          finishedAt: Value(finishedAt),
          status: Value(status),
        ));
  }

  Future<void> update(
    int id, {
    required String name,
    required String description,
    required ProjectStatus status,
    DateTime? finishedAt,
  }) async {
    final project = await getById(id);
    if (project == null) throw AppException('Проект не найден');
    var finish = finishedAt;
    if (status == ProjectStatus.completed && finish == null) {
      finish = DateTime.now();
    }
    _validate(name, project.createdAt, finish);
    await (db.update(db.projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: Value(name.trim()),
        description: Value(description.trim()),
        status: Value(status),
        finishedAt: Value(finish),
      ),
    );
  }

  /// Удаляет проект; задачи, участники, комментарии и т.д. — каскадно.
  Future<void> delete(int id) =>
      (db.delete(db.projects)..where((p) => p.id.equals(id))).go();

  // ---------------------------------------------------------------- участники

  Stream<List<MemberView>> watchMembers(int projectId) {
    final m = db.projectMembers;
    final q = db.select(m).join([
      innerJoin(db.users, db.users.id.equalsExp(m.userId)),
    ])
      ..where(m.projectId.equals(projectId))
      ..orderBy([
        OrderingTerm.asc(CustomExpression<int>(
            "CASE \"project_members\".\"role\" WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END")),
        OrderingTerm.asc(db.users.name),
      ]);
    return q.watch().map((rows) => rows
        .map((r) => MemberView(member: r.readTable(m), user: r.readTable(db.users)))
        .toList());
  }

  Future<List<MemberView>> getMembers(int projectId) => watchMembers(projectId).first;

  Future<bool> isMember(int projectId, int userId) async {
    final m = db.projectMembers;
    final c = m.id.count();
    final q = db.selectOnly(m)
      ..addColumns([c])
      ..where(m.projectId.equals(projectId) & m.userId.equals(userId));
    return (await q.map((r) => r.read(c)!).getSingle()) > 0;
  }

  Future<List<User>> usersNotInProject(int projectId) {
    final inProject = db.selectOnly(db.projectMembers)
      ..addColumns([db.projectMembers.userId])
      ..where(db.projectMembers.projectId.equals(projectId));
    return (db.select(db.users)
          ..where((u) => u.id.isNotInQuery(inProject))
          ..orderBy([(u) => OrderingTerm.asc(u.name)])
          ..limit(500))
        .get();
  }

  Future<int> addMember(int projectId, int userId,
      {MemberRole role = MemberRole.member}) async {
    if (await getById(projectId) == null) throw AppException('Проект не найден');
    if (await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull() ==
        null) {
      throw AppException('Пользователь не найден');
    }
    if (await isMember(projectId, userId)) {
      throw AppException('Пользователь уже состоит в этом проекте');
    }
    try {
      return await db.into(db.projectMembers).insert(
            ProjectMembersCompanion.insert(
              projectId: projectId,
              userId: userId,
              role: Value(role),
            ),
          );
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw AppException('Пользователь уже состоит в этом проекте');
      }
      rethrow;
    }
  }

  Future<int> _ownerCount(int projectId) async {
    final m = db.projectMembers;
    final c = m.id.count();
    return (db.selectOnly(m)
          ..addColumns([c])
          ..where(m.projectId.equals(projectId) &
              m.role.equals(MemberRole.owner.name)))
        .map((r) => r.read(c)!)
        .getSingle();
  }

  /// Нельзя понизить единственного Owner проекта.
  Future<void> setRole(int memberId, MemberRole role) async {
    final m = await (db.select(db.projectMembers)
          ..where((x) => x.id.equals(memberId)))
        .getSingleOrNull();
    if (m == null) throw AppException('Участник не найден');
    if (m.role == MemberRole.owner &&
        role != MemberRole.owner &&
        await _ownerCount(m.projectId) <= 1) {
      throw AppException('В проекте должен остаться хотя бы один Owner');
    }
    await (db.update(db.projectMembers)..where((x) => x.id.equals(memberId)))
        .write(ProjectMembersCompanion(role: Value(role)));
  }

  /// Нельзя удалить участника, пока за ним числятся незавершённые задачи проекта.
  Future<void> removeMember(int projectId, int userId) async {
    final member = await (db.select(db.projectMembers)
          ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
        .getSingleOrNull();
    if (member != null &&
        member.role == MemberRole.owner &&
        await _ownerCount(projectId) <= 1) {
      throw AppException('Нельзя удалить единственного Owner проекта');
    }
    final t = db.tasks;
    final c = t.id.count();
    final open = await (db.selectOnly(t)
          ..addColumns([c])
          ..where(t.projectId.equals(projectId) &
              t.assigneeId.equals(userId) &
              t.deletedAt.isNull() &
              t.status.isIn([TaskStatus.todo.name, TaskStatus.inProgress.name])))
        .map((r) => r.read(c)!)
        .getSingle();
    if (open > 0) {
      throw AppException(
          'У участника есть незавершённые задачи в проекте ($open). Сначала переназначьте их.');
    }
    await (db.delete(db.projectMembers)
          ..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
        .go();
  }
}
