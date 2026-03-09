import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class OfflineAction {
  const OfflineAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OfflineAction.fromMap(Map<String, dynamic> map) {
    return OfflineAction(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

typedef OfflineActionHandler = Future<void> Function(OfflineAction action);

class OfflineActionQueue {
  OfflineActionQueue(this._box);

  final Box<String> _box;
  static const _uuid = Uuid();

  static Future<OfflineActionQueue> open() async {
    final box = await Hive.openBox<String>('offline_actions');
    return OfflineActionQueue(box);
  }

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final action = OfflineAction(
      id: _uuid.v4(),
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _box.put(action.id, jsonEncode(action.toMap()));
  }

  Future<List<OfflineAction>> list() async {
    return _box.values
        .map(
          (raw) =>
              OfflineAction.fromMap(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> drain(OfflineActionHandler handler) async {
    final actions = await list();
    for (final action in actions) {
      try {
        await handler(action);
        await _box.delete(action.id);
      } catch (_) {
        // Stop on first failure to keep ordering guarantees.
        break;
      }
    }
  }
}
