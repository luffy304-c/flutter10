import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/app_exception.dart';
import '../models/enums.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isUniqueViolation(Object e) =>
    e.toString().toUpperCase().contains('UNIQUE CONSTRAINT');

class UserRepository {
  UserRepository(this.db);
  final AppDatabase db;

  Stream<List<User>> watchAll() => (db.select(db.users)
        ..orderBy([(u) => OrderingTerm.asc(u.name)]))
      .watch();

  Future<List<User>> getAll() => (db.select(db.users)
        ..orderBy([(u) => OrderingTerm.asc(u.name)]))
      .get();

  Future<User?> getById(int id) =>
      (db.select(db.users)..where((u) => u.id.equals(id))).getSingleOrNull();

  ({String name, String email}) _validate(String name, String email) {
    final n = name.trim();
    final e = email.trim().toLowerCase();
    if (n.isEmpty) throw AppException('Введите имя пользователя');
    if (n.length > 100) throw AppException('Имя слишком длинное');
    if (!_emailRe.hasMatch(e)) throw AppException('Некорректный email');
    return (name: n, email: e);
  }

  Future<void> _ensureEmailFree(String email, {int? exceptId}) async {
    final q = db.select(db.users)..where((u) => u.email.equals(email));
    if (exceptId != null) q.where((u) => u.id.equals(exceptId).not());
    if (await q.getSingleOrNull() != null) {
      throw AppException('Пользователь с email $email уже существует');
    }
  }

  Future<int> create({
    required String name,
    required String email,
    DateTime? registeredAt,
  }) async {
    final v = _validate(name, email);
    await _ensureEmailFree(v.email);
    try {
      return await db.into(db.users).insert(UsersCompanion.insert(
            name: v.name,
            email: v.email,
            registeredAt: registeredAt ?? DateTime.now(),
          ));
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw AppException('Пользователь с email ${v.email} уже существует');
      }
      rethrow;
    }
  }

  Future<void> update(int id, {required String name, required String email}) async {
    final v = _validate(name, email);
    await _ensureEmailFree(v.email, exceptId: id);
    try {
      await (db.update(db.users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(name: Value(v.name), email: Value(v.email)),
      );
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw AppException('Пользователь с email ${v.email} уже существует');
      }
      rethrow;
    }
  }

  /// Количество незавершённых задач (todo / inProgress), закреплённых за
  /// пользователем (включая задачи в корзине).
  Future<int> countUnfinishedTasks(int userId) async {
    final t = db.tasks;
    final cnt = t.id.count();
    final q = db.selectOnly(t)
      ..addColumns([cnt])
      ..where(t.assigneeId.equals(userId) &
          t.status.isIn([TaskStatus.todo.name, TaskStatus.inProgress.name]));
    return (await q.map((r) => r.read(cnt)!).getSingle());
  }

  /// Удаление пользователя. Запрещено при незавершённых задачах.
  /// Участие в проектах и комментарии удаляются каскадом, исполнитель
  /// завершённых задач обнуляется (SET NULL).
  Future<void> delete(int id) async {
    final open = await countUnfinishedTasks(id);
    if (open > 0) {
      throw AppException(
          'Нельзя удалить пользователя: за ним закреплено незавершённых задач — $open');
    }
    await (db.delete(db.users)..where((u) => u.id.equals(id))).go();
  }
}
