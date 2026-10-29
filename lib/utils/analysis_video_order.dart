typedef AnalysisVideoRank = ({
  bool followed,
  String? language,
  String? publishedAt,
  String label,
  String id,
});

int compareAnalysisVideoRanks(
  AnalysisVideoRank a,
  AnalysisVideoRank b,
  String? preferredLanguage,
) {
  if (a.followed != b.followed) return a.followed ? -1 : 1;
  String primary(String? value) =>
      (value ?? '').toLowerCase().split(RegExp('[-_]')).first;
  final preferred = primary(preferredLanguage);
  final aMatches = preferred.isNotEmpty && primary(a.language) == preferred;
  final bMatches = preferred.isNotEmpty && primary(b.language) == preferred;
  if (aMatches != bMatches) return aMatches ? -1 : 1;
  final newest =
      (DateTime.tryParse(b.publishedAt ?? '')?.millisecondsSinceEpoch ?? 0)
          .compareTo(
            DateTime.tryParse(a.publishedAt ?? '')?.millisecondsSinceEpoch ?? 0,
          );
  if (newest != 0) return newest;
  final name = a.label.toLowerCase().compareTo(b.label.toLowerCase());
  return name != 0 ? name : a.id.compareTo(b.id);
}
