/// Rewrites queued child payloads that still point at an optimistic
/// `pending_<actionId>` project id after the server create returns a real id.
Map<String, dynamic> remapPendingProjectId({
  required Map<String, dynamic> payload,
  required String pendingId,
  required String serverId,
}) {
  if (pendingId.isEmpty || serverId.isEmpty || pendingId == serverId) {
    return payload;
  }
  final next = Map<String, dynamic>.from(payload);
  if (next['projectId'] == pendingId) {
    next['projectId'] = serverId;
  }
  if (next['previousProjectId'] == pendingId) {
    next['previousProjectId'] = serverId;
  }
  return next;
}
