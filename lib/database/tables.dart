import 'package:drift/drift.dart';

import '../models/enums.dart';

/// users — пользователи.
@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  // Email хранится в нижнем регистре, UNIQUE.
  TextColumn get email => text().withLength(min: 3, max: 200).unique()();
  DateTimeColumn get registeredAt => dateTime()();
}

/// projects — проекты.
@DataClassName('Project')
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get status => textEnum<ProjectStatus>()
      .withDefault(const Constant('active'))();
}

/// project_members — связь Many-to-Many users <-> projects.
@DataClassName('ProjectMember')
@TableIndex(name: 'idx_members_user', columns: {#userId})
class ProjectMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get role =>
      textEnum<MemberRole>().withDefault(const Constant('member'))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {projectId, userId},
      ];
}

/// tasks — задачи (One-to-Many от projects; assignee -> users).
@DataClassName('Task')
@TableIndex(name: 'idx_tasks_project', columns: {#projectId})
@TableIndex(name: 'idx_tasks_assignee', columns: {#assigneeId})
@TableIndex(name: 'idx_tasks_status', columns: {#status})
@TableIndex(name: 'idx_tasks_priority', columns: {#priority})
@TableIndex(name: 'idx_tasks_deadline', columns: {#deadline})
@TableIndex(name: 'idx_tasks_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_tasks_deleted_at', columns: {#deletedAt})
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get assigneeId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  // Поле добавлено в схеме версии 2 (см. миграцию).
  TextColumn get priority =>
      textEnum<TaskPriority>().withDefault(const Constant('medium'))();
  TextColumn get status =>
      textEnum<TaskStatus>().withDefault(const Constant('todo'))();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  // Soft delete.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// comments — комментарии к задачам.
@DataClassName('Comment')
@TableIndex(name: 'idx_comments_task', columns: {#taskId})
class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get authorId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text().withLength(min: 1, max: 2000)();
  DateTimeColumn get createdAt => dateTime()();
}

/// attachments — вложения (хранится путь, а не содержимое).
@DataClassName('Attachment')
@TableIndex(name: 'idx_attachments_task', columns: {#taskId})
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text().withLength(min: 1, max: 255)();
  TextColumn get filePath => text()();
  DateTimeColumn get addedAt => dateTime()();
}

/// task_history — история изменений задач.
@DataClassName('TaskHistoryEntry')
@TableIndex(name: 'idx_history_task', columns: {#taskId})
class TaskHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<HistoryKind>()();
  TextColumn get oldStatus => textEnum<TaskStatus>().nullable()();
  TextColumn get newStatus => textEnum<TaskStatus>()();
  TextColumn get details => text().nullable()();
  IntColumn get changedBy => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get changedAt => dateTime()();
  // true — это изменение статуса уже было отменено (Undo).
  BoolColumn get undone => boolean().withDefault(const Constant(false))();
}
