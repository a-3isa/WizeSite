import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePage<T> {
  const FirestorePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;
}
