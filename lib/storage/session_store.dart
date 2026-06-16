import 'package:hive/hive.dart';

part 'session_store.g.dart';

@HiveType(typeId: 0)
class SessionConfig extends HiveObject {
  @HiveField(0)
  final String backgroundModel;

  @HiveField(1)
  final bool faceMeshEnabled;

  @HiveField(2)
  final DateTime createdAt;

  SessionConfig({
    required this.backgroundModel,
    required this.faceMeshEnabled,
    required this.createdAt,
  });
}

class SessionStore {
  static const _boxName = 'sessions';

  Future<Box<SessionConfig>> get _box => Hive.openBox<SessionConfig>(_boxName);

  Future<void> saveSession(SessionConfig config) async {
    final box = await _box;
    await box.add(config);
  }

  Future<List<SessionConfig>> getAllSessions() async {
    final box = await _box;
    return box.values.toList();
  }

  Future<void> clear() async {
    final box = await _box;
    await box.clear();
  }
}
