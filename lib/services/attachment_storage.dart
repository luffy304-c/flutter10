import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Копирует выбранный файл в каталог приложения и возвращает локальный путь.
class AttachmentStorage {
  Future<String> store(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(dir.path, 'attachments'));
    await target.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourcePath)}';
    final copied = await File(sourcePath).copy(p.join(target.path, name));
    return copied.path;
  }

  Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
