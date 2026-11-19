import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/task_repository.dart';

/// Состояние списка задач: фильтры, сортировка, поиск и пагинация.
/// Данные приходят из Repository через реактивный Drift-stream (watch()).
class TaskListController extends ChangeNotifier {
  TaskListController(this._repo, {TaskFilter initial = const TaskFilter()})
      : _filter = initial,
        _locked = initial {
    _rebuild();
  }

  static const pageSize = 50;

  final TaskRepository _repo;
  final TaskFilter _locked; // фиксированные условия (проект / исполнитель)
  TaskFilter _filter;
  int _limit = pageSize;

  late Stream<List<TaskView>> tasks;
  late Stream<int> total;

  TaskFilter get filter => _filter;
  int get limit => _limit;

  void _rebuild() {
    tasks = _repo.watchTasks(_filter, limit: _limit);
    total = _repo.watchCount(_filter);
    notifyListeners();
  }

  void _apply(TaskFilter f) {
    _filter = f;
    _limit = pageSize;
    _rebuild();
  }

  void setSearch(String s) => _apply(_filter.copyWith(search: s));
  void setStatus(TaskStatus? s) => _apply(_filter.copyWith(status: () => s));
  void setPriority(TaskPriority? p) => _apply(_filter.copyWith(priority: () => p));
  void setAssignee(int? id) {
    if (_locked.assigneeId != null) return;
    _apply(_filter.copyWith(assigneeId: () => id));
  }

  void setSort(TaskSortField field, {bool? ascending}) => _apply(_filter.copyWith(
      sortField: field,
      ascending: ascending ?? (field == TaskSortField.deadline)));

  void toggleDirection() =>
      _apply(_filter.copyWith(ascending: !_filter.ascending));

  void reset() => _apply(_locked);

  /// Пагинация: увеличиваем окно выборки.
  void loadMore() {
    _limit += pageSize;
    _rebuild();
  }

  bool get hasLockedAssignee => _locked.assigneeId != null;
}
