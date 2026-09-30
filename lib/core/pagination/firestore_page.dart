/// One page of a paginated list. Backend-neutral despite the historical name:
/// [nextCursor] is opaque to callers (a Firestore `DocumentSnapshot` for the
/// Firebase repositories, a `LocalPageCursor` for the local replica). Screens
/// only hand it back to the repository that produced it.
class FirestorePage<T> {
  const FirestorePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final Object? nextCursor;
}
