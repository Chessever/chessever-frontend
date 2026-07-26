enum RankingActivity { active, all }

enum RankingTimeControl { classical, rapid, blitz }

extension RankingTimeControlData on RankingTimeControl {
  String get ratingColumn => switch (this) {
    RankingTimeControl.classical => 'rating',
    RankingTimeControl.rapid => 'rapid_rating',
    RankingTimeControl.blitz => 'blitz_rating',
  };

  String get label => switch (this) {
    RankingTimeControl.classical => 'Classical',
    RankingTimeControl.rapid => 'Rapid',
    RankingTimeControl.blitz => 'Blitz',
  };
}

enum RankingCategory { overall, women, juniors, girls }

extension RankingCategoryData on RankingCategory {
  bool get requiresFemale =>
      this == RankingCategory.women || this == RankingCategory.girls;

  bool get requiresJunior =>
      this == RankingCategory.juniors || this == RankingCategory.girls;

  String get label => switch (this) {
    RankingCategory.overall => 'Overall',
    RankingCategory.women => 'Women',
    RankingCategory.juniors => 'Juniors',
    RankingCategory.girls => 'Girls',
  };
}

bool isFideInactiveFlag(String? flag) =>
    flag?.toLowerCase().contains('i') ?? false;

class RankingFilters {
  const RankingFilters({
    required this.activity,
    required this.timeControl,
    required this.category,
  });

  static const defaults = RankingFilters(
    activity: RankingActivity.active,
    timeControl: RankingTimeControl.classical,
    category: RankingCategory.overall,
  );

  final RankingActivity activity;
  final RankingTimeControl timeControl;
  final RankingCategory category;

  RankingFilters copyWith({
    RankingActivity? activity,
    RankingTimeControl? timeControl,
    RankingCategory? category,
  }) {
    return RankingFilters(
      activity: activity ?? this.activity,
      timeControl: timeControl ?? this.timeControl,
      category: category ?? this.category,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RankingFilters &&
        other.activity == activity &&
        other.timeControl == timeControl &&
        other.category == category;
  }

  @override
  int get hashCode => Object.hash(activity, timeControl, category);
}
