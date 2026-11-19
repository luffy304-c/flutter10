/// Статусы задачи.
enum TaskStatus {
  todo('К выполнению'),
  inProgress('В работе'),
  done('Завершена'),
  cancelled('Отменена');

  const TaskStatus(this.label);
  final String label;

  /// Незавершённая задача (ещё требует работы).
  bool get isOpen => this == todo || this == inProgress;
}

/// Приоритеты задачи.
enum TaskPriority {
  low('Низкий'),
  medium('Средний'),
  high('Высокий'),
  critical('Критический');

  const TaskPriority(this.label);
  final String label;
}

/// Статус проекта.
enum ProjectStatus {
  active('Активный'),
  completed('Завершённый'),
  archived('Архивный');

  const ProjectStatus(this.label);
  final String label;
}

/// Роль участника проекта.
enum MemberRole {
  owner('Owner'),
  admin('Admin'),
  member('Member');

  const MemberRole(this.label);
  final String label;
}

/// Тип записи в истории задачи.
enum HistoryKind {
  created('Создание'),
  status('Смена статуса'),
  reassign('Смена исполнителя'),
  undo('Отмена изменения');

  const HistoryKind(this.label);
  final String label;
}
