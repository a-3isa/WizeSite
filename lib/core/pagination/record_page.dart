/// One page of a paginated list. [nextCursor] is opaque to callers (a
/// `LocalPageCursor`); screens only hand it back to the repository that
/// produced it.
class RecordPage<T> {
  const RecordPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final Object? nextCursor;
}
