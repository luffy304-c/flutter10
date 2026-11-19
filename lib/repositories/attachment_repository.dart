import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/app_exception.dart';

class AttachmentRepository {
  AttachmentRepository(this.db);
  final AppDatabase db;

  Stream<List<Attachment>> watchForTask(int taskId) => (db.select(db.attachments)
        ..where((a) => a.taskId.equals(taskId))
        ..orderBy([(a) => OrderingTerm.desc(a.addedAt)]))
      .watch();

  /// В БД сохраняется только путь к файлу.
  Future<int> add({
    required int taskId,
    required String fileName,
    required String filePath,
  }) async {
    if (fileName.trim().isEmpty || filePath.trim().isEmpty) {
      throw AppException('Не указан файл');
    }
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task == null || task.deletedAt != null) {
      throw AppException('Задача не существует');
    }
    return db.into(db.attachments).insert(AttachmentsCompanion.insert(
          taskId: taskId,
          fileName: fileName,
          filePath: filePath,
          addedAt: DateTime.now(),
        ));
  }

  Future<void> delete(int id) =>
      (db.delete(db.attachments)..where((a) => a.id.equals(id))).go();
}
