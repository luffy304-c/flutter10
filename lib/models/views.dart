import '../database/app_database.dart';
import 'enums.dart';

/// Задача вместе с именем проекта и исполнителя.
class TaskView {
  const TaskView({
    required this.task,
    required this.projectName,
    this.assigneeName,
  });
  final Task task;
  final String projectName;
  final String? assigneeName;
}

enum TaskSortField { createdAt, deadline }

/// Параметры фильтрации / поиска / сортировки списка задач.
class TaskFilter {
  const TaskFilter({
    this.projectId,
    this.assigneeId,
    this.status,
    this.priority,
    this.search = '',
    this.sortField = TaskSortField.createdAt,
    this.ascending = false,
    this.onlyDeleted = false,
  });

  final int? projectId;
  final int? assigneeId;
  final TaskStatus? status;
  final TaskPriority? priority;
  final String search;
  final TaskSortField sortField;
  final bool ascending;
  final bool onlyDeleted;

  TaskFilter copyWith({
    int? Function()? projectId,
    int? Function()? assigneeId,
    TaskStatus? Function()? status,
    TaskPriority? Function()? priority,
    String? search,
    TaskSortField? sortField,
    bool? ascending,
    bool? onlyDeleted,
  }) {
    return TaskFilter(
      projectId: projectId != null ? projectId() : this.projectId,
      assigneeId: assigneeId != null ? assigneeId() : this.assigneeId,
      status: status != null ? status() : this.status,
      priority: priority != null ? priority() : this.priority,
      search: search ?? this.search,
      sortField: sortField ?? this.sortField,
      ascending: ascending ?? this.ascending,
      onlyDeleted: onlyDeleted ?? this.onlyDeleted,
    );
  }
}

/// Проект + прогресс.
class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.totalTasks,
    required this.doneTasks,
    required this.countedTasks,
  });
  final Project project;

  /// Все не удалённые задачи.
  final int totalTasks;
  final int doneTasks;

  /// Задачи без учёта отменённых — база для процента выполнения.
  final int countedTasks;

  double get percent => countedTasks == 0 ? 0 : doneTasks * 100 / countedTasks;
}

class MemberView {
  const MemberView({required this.member, required this.user});
  final ProjectMember member;
  final User user;
}

class CommentView {
  const CommentView({required this.comment, required this.authorName});
  final Comment comment;
  final String authorName;
}

class HistoryView {
  const HistoryView({required this.entry, this.userName});
  final TaskHistoryEntry entry;
  final String? userName;
}

class AssigneeCount {
  const AssigneeCount(this.userId, this.name, this.count);
  final int userId;
  final String name;
  final int count;
}

class DashboardStats {
  const DashboardStats({
    required this.projects,
    required this.totalTasks,
    required this.doneTasks,
    required this.openTasks,
    required this.overdueTasks,
    required this.byPriority,
    required this.byAssignee,
    required this.projectProgress,
  });
  final int projects;
  final int totalTasks;
  final int doneTasks;
  final int openTasks;
  final int overdueTasks;
  final Map<TaskPriority, int> byPriority;
  final List<AssigneeCount> byAssignee;
  final List<ProjectSummary> projectProgress;
}
