import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' as sql;

import '../models/enums.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Регистрирует SQL-функцию ulower() — lower() с поддержкой кириллицы
/// (встроенный lower() SQLite работает только с ASCII).
void registerSqlFunctions(sql.CommonDatabase db) {
  db.createFunction(
    functionName: 'ulower',
    argumentCount: const sql.AllowedArgumentCount(1),
    deterministic: true,
    function: (args) => (args[0] as String?)?.toLowerCase(),
  );
}

@DriftDatabase(
  tables: [
    Users,
    Projects,
    ProjectMembers,
    Tasks,
    Comments,
    Attachments,
    TaskHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// База в памяти (для тестов).
  AppDatabase.inMemory() : super(NativeDatabase.memory(setup: registerSqlFunctions));

  /// База-файл в каталоге документов приложения.
  factory AppDatabase.file(String fileName) {
    return AppDatabase(
      LazyDatabase(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, fileName));
        return NativeDatabase.createInBackground(
          file,
          setup: registerSqlFunctions,
        );
      }),
    );
  }

  /// v1 — задачи без priority; v2 — добавлено поле priority.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'
            await m.addColumn(tasks, tasks.priority);
            // Явно гарантируем medium для всех ранее созданных задач.
            await customStatement(
              "UPDATE tasks SET priority = 'medium' "
              "WHERE priority IS NULL OR priority = ''",
            );
            await m.createIndex(idxTasksPriority);
          }
        },
        beforeOpen: (details) async {
          // Без этого SQLite не проверяет внешние ключи.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
