import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../repositories/user_repository.dart';

/// Глобальное состояние: «текущий пользователь» — от его имени пишется
/// история изменений и комментарии.
class AppController extends ChangeNotifier {
  AppController(this._users) {
    _sub = _users.watchAll().listen(_onUsers);
  }

  final UserRepository _users;
  late final StreamSubscription<List<User>> _sub;
  List<User> users = const [];
  int? _currentUserId;

  User? get currentUser {
    for (final u in users) {
      if (u.id == _currentUserId) return u;
    }
    return users.isEmpty ? null : users.first;
  }

  int? get actorId => currentUser?.id;

  void setCurrent(int id) {
    _currentUserId = id;
    notifyListeners();
  }

  void _onUsers(List<User> list) {
    users = list;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
