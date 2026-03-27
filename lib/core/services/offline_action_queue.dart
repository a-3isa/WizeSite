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
    this.retryCount = 0,
    this.lastError,
    this.status = OfflineActionStatus.pending,
    this.nextAttemptAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final String status;
  final DateTime? nextAttemptAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastError': lastError,
    'status': status,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
  };

  factory OfflineAction.fromMap(Map<String, dynamic> map) {
    return OfflineAction(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
      status: map['status'] as String? ?? OfflineActionStatus.pending,
      nextAttemptAt: map['nextAttemptAt'] == null
          ? null
          : DateTime.tryParse(map['nextAttemptAt'] as String),
    );
  }

  OfflineAction copyWith({
    int? retryCount,
    String? lastError,
    String? status,
    DateTime? nextAttemptAt,
    bool clearLastError = false,
    bool clearNextAttemptAt = false,
  }) {
    return OfflineAction(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      status: status ?? this.status,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }
}

abstract final class OfflineActionStatus {
  static const pending = 'pending';
  static const failed = 'failed';
  static const deadLetter = 'dead_letter';
}

typedef OfflineActionHandler = Future<void> Function(OfflineAction action);

class OfflineActionQueue {
  OfflineActionQueue(this._box);

  final Box<String> _box;
  Future<void>? _activeDrain;
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

  Future<List<OfflineAction>> list({bool includeDeadLetters = false}) async {
    return _box.values
        .map(
          (raw) =>
              OfflineAction.fromMap(jsonDecode(raw) as Map<String, dynamic>),
        )
        .where(
          (action) =>
              includeDeadLetters ||
              action.status != OfflineActionStatus.deadLetter,
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Stream<List<OfflineAction>> watch({bool includeDeadLetters = false}) async* {
    yield await list(includeDeadLetters: includeDeadLetters);
    await for (final _ in _box.watch()) {
      yield await list(includeDeadLetters: includeDeadLetters);
    }
  }

  Future<void> save(OfflineAction action) async {
    await _box.put(action.id, jsonEncode(action.toMap()));
  }

  Future<void> drain(
    OfflineActionHandler handler, {
    int maxRetries = 3,
    Duration retryBackoff = const Duration(minutes: 1),
  }) async {
    if (_activeDrain != null) {
      await _activeDrain;
      return;
    }

    final completer = Completer<void>();
    _activeDrain = completer.future;

    try {
      final now = DateTime.now();
      final actions = await list();
      for (final action in actions) {
        if (action.nextAttemptAt != null &&
            action.nextAttemptAt!.isAfter(now)) {
          continue;
        }
        try {
          await handler(action);
          await _box.delete(action.id);
        } catch (error) {
          final errorText = error.toString();
          final isTerminalFailure = _isTerminalFailure(errorText);
          final nextRetryCount = action.retryCount + 1;
          if (isTerminalFailure || nextRetryCount >= maxRetries) {
            await save(
              action.copyWith(
                retryCount: nextRetryCount,
                lastError: errorText,
                status: OfflineActionStatus.deadLetter,
                clearNextAttemptAt: true,
              ),
            );
          } else {
            await save(
              action.copyWith(
                retryCount: nextRetryCount,
                lastError: errorText,
                status: OfflineActionStatus.failed,
                nextAttemptAt: DateTime.now().add(retryBackoff),
              ),
            );
          }
          // Stop on first failure to keep ordering guarantees.
          break;
        }
      }
    } finally {
      completer.complete();
      _activeDrain = null;
    }
  }

  Future<int> pendingCount() async {
    final actions = await list();
    return actions
        .where((action) => action.status != OfflineActionStatus.deadLetter)
        .length;
  }

  Future<List<OfflineAction>> deadLetters() async {
    final actions = await list(includeDeadLetters: true);
    return actions
        .where((action) => action.status == OfflineActionStatus.deadLetter)
        .toList();
  }

  bool _isTerminalFailure(String errorText) {
    final text = errorText.toLowerCase();
    return text.contains('failed-precondition') ||
        text.contains('limit_reached') ||
        text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('invalid-argument') ||
        text.contains('invalid_argument');
  }
}
