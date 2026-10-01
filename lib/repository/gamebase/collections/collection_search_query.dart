/// One immutable query shared by all three catalog tabs. Filters intersect;
/// sorting never changes which items match, and pages use the same query.
class CollectionSearchQuery {
  const CollectionSearchQuery({
    this.text = '',
    this.eco = '',
    this.result = '',
    this.year,
    this.minYear,
    this.maxYear,
    this.author = '',
    this.authorId = '',
    this.annotated = false,
    this.sort = 'default',
  });
  final String text;
  final String eco;
  final String result;
  final int? year;
  final int? minYear;
  final int? maxYear;
  final String author;
  final String authorId;

  factory CollectionSearchQuery.recentYears() {
    final year = DateTime.now().year;
    return CollectionSearchQuery(minYear: year - 1, maxYear: year);
  }
  final bool annotated;
  final String sort;

  int get filterCount =>
      (eco.isEmpty ? 0 : 1) +
      (result.isEmpty ? 0 : 1) +
      (year == null && minYear == null && maxYear == null ? 0 : 1) +
      (author.isEmpty && authorId.isEmpty ? 0 : 1) +
      (annotated ? 1 : 0) +
      (sort == 'default' ? 0 : 1);
  bool get isActive => text.trim().isNotEmpty || filterCount > 0;
  Map<String, dynamic> get parameters => {
    if (text.trim().isNotEmpty) 'q': text.trim(),
    if (eco.isNotEmpty) 'eco': eco.toUpperCase(),
    if (result.isNotEmpty) 'result': result,
    if (year != null) 'year': year,
    if (minYear != null) 'minYear': minYear,
    if (maxYear != null) 'maxYear': maxYear,
    if (author.isNotEmpty) 'author': author,
    if (authorId.isNotEmpty) 'authorId': authorId,
    if (annotated) 'annotated': 'true',
    if (sort != 'default') 'sort': sort,
  };
  CollectionSearchQuery withText(String value) => CollectionSearchQuery(
    text: value,
    eco: eco,
    result: result,
    year: year,
    minYear: minYear,
    maxYear: maxYear,
    author: author,
    authorId: authorId,
    annotated: annotated,
    sort: sort,
  );
  @override
  bool operator ==(Object other) =>
      other is CollectionSearchQuery &&
      text == other.text &&
      eco == other.eco &&
      result == other.result &&
      year == other.year &&
      minYear == other.minYear &&
      maxYear == other.maxYear &&
      author == other.author &&
      authorId == other.authorId &&
      annotated == other.annotated &&
      sort == other.sort;
  @override
  int get hashCode => Object.hash(
    text,
    eco,
    result,
    year,
    minYear,
    maxYear,
    author,
    authorId,
    annotated,
    sort,
  );
}
