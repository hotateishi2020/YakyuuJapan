/// Unknown creation dates never produce a misleading new marker.
bool newsAddedAfter(dynamic createdAt, DateTime? readAt) {
  final created = DateTime.tryParse('${createdAt ?? ''}');
  return created != null && (readAt == null || created.isAfter(readAt));
}
