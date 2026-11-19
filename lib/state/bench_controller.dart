import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../services/benchmark_service.dart';

/// Состояние экрана «Производительность»: тестовая БД 1000/100/10000
/// создаётся в отдельном файле, не затрагивая основные данные.
class BenchController extends ChangeNotifier {
  bool running = false;
  String stage = '';
  String? error;
  List<BenchResult> results = const [];
  Duration? seedTime;
  int users = 0, projects = 0, tasks = 0;

  Future<void> runFull() async {
    running = true;
    error = null;
    results = const [];
    notifyListeners();
    AppDatabase? db;
    try {
      final dir = await getApplicationDocumentsDirectory();
      const name = 'taskflow_bench.sqlite';
      for (final ext in ['', '-wal', '-shm', '-journal']) {
        final f = File(p.join(dir.path, '$name$ext'));
        if (await f.exists()) await f.delete();
      }
      db = AppDatabase.file(name);
      final service = BenchmarkService(db);
      final sw = Stopwatch()..start();
      await service.seed(onProgress: (s) {
        stage = s;
        notifyListeners();
      });
      seedTime = sw.elapsed;
      users = 1000;
      projects = 100;
      tasks = 10000;
      stage = 'Замеры запросов…';
      notifyListeners();
      results = await service.run(repeats: 5);
      stage = 'Готово';
    } catch (e) {
      error = '$e';
    } finally {
      await db?.close();
      running = false;
      notifyListeners();
    }
  }
}
