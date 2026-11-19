/// Бизнес-ошибка с сообщением, пригодным для показа пользователю.
class AppException implements Exception {
  AppException(this.message);
  final String message;

  @override
  String toString() => message;
}
