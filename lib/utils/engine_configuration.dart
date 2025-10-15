import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kMinStockfishDepth = 1;
const int kMaxStockfishDepth = 30;
const int kMinPrincipalVariationCount = 1;
const int kMaxPrincipalVariationCount = 5;

@immutable
class StockfishSettings {
  const StockfishSettings({
    this.stockfishDepth = 15,
    this.principalVariationCount = 3,
    this.isEvaluationGaugeEnabled = true,
  })  : assert(
          stockfishDepth >= kMinStockfishDepth &&
              stockfishDepth <= kMaxStockfishDepth,
          'Depth must be between $kMinStockfishDepth and $kMaxStockfishDepth',
        ),
        assert(
          principalVariationCount >= kMinPrincipalVariationCount &&
              principalVariationCount <= kMaxPrincipalVariationCount,
          'Principal variation count must be between '
          '$kMinPrincipalVariationCount and $kMaxPrincipalVariationCount',
        );

  final int stockfishDepth;
  final int principalVariationCount;
  final bool isEvaluationGaugeEnabled;

  StockfishSettings copyWith({
    int? stockfishDepth,
    int? principalVariationCount,
    bool? isEvaluationGaugeEnabled,
  }) {
    return StockfishSettings(
      stockfishDepth: stockfishDepth ?? this.stockfishDepth,
      principalVariationCount:
          principalVariationCount ?? this.principalVariationCount,
      isEvaluationGaugeEnabled:
          isEvaluationGaugeEnabled ?? this.isEvaluationGaugeEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StockfishSettings &&
        other.stockfishDepth == stockfishDepth &&
        other.principalVariationCount == principalVariationCount &&
        other.isEvaluationGaugeEnabled == isEvaluationGaugeEnabled;
  }

  @override
  int get hashCode =>
      stockfishDepth.hashCode ^
      principalVariationCount.hashCode ^
      isEvaluationGaugeEnabled.hashCode;
}

class StockfishSettingsNotifier extends StateNotifier<StockfishSettings> {
  StockfishSettingsNotifier() : super(const StockfishSettings());

  void setDepth(int depth) {
    final clampedDepth =
        depth < kMinStockfishDepth
            ? kMinStockfishDepth
            : depth > kMaxStockfishDepth
            ? kMaxStockfishDepth
            : depth;
    if (clampedDepth == state.stockfishDepth) return;
    state = state.copyWith(stockfishDepth: clampedDepth);
  }

  void setPrincipalVariationCount(int count) {
    final clampedCount =
        count < kMinPrincipalVariationCount
            ? kMinPrincipalVariationCount
            : count > kMaxPrincipalVariationCount
            ? kMaxPrincipalVariationCount
            : count;
    if (clampedCount == state.principalVariationCount) return;
    state = state.copyWith(principalVariationCount: clampedCount);
  }

  void setEvaluationGaugeEnabled(bool isEnabled) {
    if (isEnabled == state.isEvaluationGaugeEnabled) return;
    state = state.copyWith(isEvaluationGaugeEnabled: isEnabled);
  }
}

final stockfishSettingsProvider = StateNotifierProvider<
  StockfishSettingsNotifier,
  StockfishSettings
>((ref) => StockfishSettingsNotifier());
