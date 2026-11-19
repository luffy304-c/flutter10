import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/app_exception.dart';
import '../models/views.dart';

class CommentRepository {
  CommentRepository(this.db);
  final AppDatabase db;

  Stream<List<CommentView>> watchForTask(int taskId) {
    final c = db.comments;
    final q = db.select(c).join([
      innerJoin(db.users, db.users.id.equalsExp(c.authorId)),
    ])
      ..where(c.taskId.equals(taskId))
      ..orderBy([OrderingTerm.asc(c.createdAt), OrderingTerm.asc(c.id)]);
    return q.watch().map((rows) => rows
        .map((r) => CommentView(
            comment: r.readTable(c), authorName: r.read(db.users.name)!))
        .toList());
  }

  Future<List<CommentView>> getForTask(int taskId) => watchForTask(taskId).first;

  /// Комментарий к несуществующей (или удалённой) задаче запрещён.
  Future<int> add({
    required int taskId,
    required int authorId,
    required String text,
  }) async {
    if (text.trim().isEmpty) throw AppException('Введите текст комментария');
    return db.transaction(() async {
      final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
          .getSingleOrNull();
      if (task == null || task.deletedAt != null) {
        throw AppException('Нельзя добавить комментарий: задача не существует');
      }
      final author = await (db.select(db.users)
            ..where((u) => u.id.equals(authorId)))
          .getSingleOrNull();
      if (author == null) throw AppException('Автор не найден');
      return db.into(db.comments).insert(CommentsCompanion.insert(
            taskId: taskId,
            authorId: authorId,
            body: text.trim(),
            createdAt: DateTime.now(),
          ));
    });
  }

  /// Удалять комментарий может только его автор.
  Future<void> delete(int commentId, {required int requesterId}) async {
    final c = await (db.select(db.comments)..where((c) => c.id.equals(commentId)))
        .getSingleOrNull();
    if (c == null) return;
    if (c.authorId != requesterId) {
      throw AppException('Удалять комментарий может только его автор');
    }
    await (db.delete(db.comments)..where((c) => c.id.equals(commentId))).go();
  }
}
