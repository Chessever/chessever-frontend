import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Bottom-sheet filter UI for Library search (Gamebase database games).
///
/// Backed by `gamebaseDatabaseSearchProvider` (metadata-driven `/api/search/query`).
class LibraryGamebaseFiltersSheet extends ConsumerWidget {
  const LibraryGamebaseFiltersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);

    return searchAsync.when(
      loading:
          () => SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16.br),
                ),
              ),
              padding: EdgeInsets.symmetric(vertical: 32.h),
              child: const Center(
                child: CircularProgressIndicator(color: kWhiteColor),
              ),
            ),
          ),
      error:
          (error, _) => SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16.br),
                ),
              ),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: _InlineError(message: error.toString()),
            ),
          ),
      data: (state) {
        final filterable = state.resource.filterableColumns;

        final defaultField =
            filterable.isNotEmpty
                ? filterable.first.name
                : state.resource.primaryKey;
        final defaultOperators =
            state.resource.columnByName(defaultField)?.operators ??
            const ['eq'];
        final defaultOp =
            defaultOperators.isNotEmpty ? defaultOperators.first : 'eq';

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
            ),
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Text(
                      'Filters',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    const Spacer(),
                    _SmallTextButton(
                      label: 'Clear',
                      onTap:
                          () =>
                              ref
                                  .read(gamebaseDatabaseSearchProvider.notifier)
                                  .clearFilters(),
                      color: kRedColor,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Text(
                      'Match',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    _SegmentedControl<GamebaseFilterGroupMode>(
                      value: state.filterMode,
                      values: const [
                        GamebaseFilterGroupMode.and,
                        GamebaseFilterGroupMode.or,
                      ],
                      labels: const ['All', 'Any'],
                      onChanged:
                          ref
                              .read(gamebaseDatabaseSearchProvider.notifier)
                              .setFilterMode,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.filters.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, index) {
                      return _FilterRuleCard(
                        key: ValueKey('library-filter-$index'),
                        state: state,
                        rule: state.filters[index],
                        onChanged:
                            (rule) => ref
                                .read(gamebaseDatabaseSearchProvider.notifier)
                                .updateFilterRule(index, rule),
                        onRemove:
                            () => ref
                                .read(gamebaseDatabaseSearchProvider.notifier)
                                .removeFilterRule(index),
                      );
                    },
                  ),
                ),
                SizedBox(height: 12.h),
                _PrimaryButton(
                  label: 'Add Filter',
                  onTap: () {
                    ref
                        .read(gamebaseDatabaseSearchProvider.notifier)
                        .addFilterRule(
                          GamebaseFilterRule(
                            field: defaultField,
                            op: defaultOp,
                          ),
                        );
                  },
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterRuleCard extends StatelessWidget {
  const _FilterRuleCard({
    super.key,
    required this.state,
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final GamebaseDatabaseSearchState state;
  final GamebaseFilterRule rule;
  final ValueChanged<GamebaseFilterRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final columns = state.resource.filterableColumns;
    final selectedColumn =
        state.resource.columnByName(rule.field) ?? columns.firstOrNull;
    final operators = selectedColumn?.operators ?? const ['eq'];
    final selectedOp =
        operators.contains(rule.op)
            ? rule.op
            : (operators.isNotEmpty ? operators.first : 'eq');

    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Dropdown<String>(
                  value: selectedColumn?.name,
                  items: [
                    for (final c in columns)
                      _DropdownItem(value: c.name, label: _humanize(c.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final newColumn = state.resource.columnByName(value);
                    final newOps = newColumn?.operators ?? const ['eq'];
                    final op =
                        newOps.contains(selectedOp)
                            ? selectedOp
                            : (newOps.isNotEmpty ? newOps.first : 'eq');
                    onChanged(
                      rule.copyWith(
                        field: value,
                        op: op,
                        value: null,
                        values: null,
                        overrideValues: true,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _Dropdown<String>(
                  value: selectedOp,
                  items: [
                    for (final op in operators)
                      _DropdownItem(value: op, label: _operatorLabel(op)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(
                      rule.copyWith(
                        op: value,
                        value: null,
                        values: null,
                        overrideValues: true,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: 10.w),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: kRedColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: kRedColor,
                    size: 18.ic,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: _ValueEditor(
                  column: selectedColumn,
                  op: selectedOp,
                  rule: rule,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(width: 10.w),
              _ToggleChip(
                label: 'NOT',
                isActive: rule.negated,
                onTap: () => onChanged(rule.copyWith(negated: !rule.negated)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueEditor extends StatelessWidget {
  const _ValueEditor({
    required this.column,
    required this.op,
    required this.rule,
    required this.onChanged,
  });

  final GamebaseSearchColumnMetadata? column;
  final String op;
  final GamebaseFilterRule rule;
  final ValueChanged<GamebaseFilterRule> onChanged;

  @override
  Widget build(BuildContext context) {
    final needsNoValue = op == 'isNull' || op == 'isNotNull';
    final needsMultiple = op == 'in' || op == 'nin' || op == 'between';

    if (needsNoValue) {
      return Text(
        'No value',
        style: AppTypography.textSmRegular.copyWith(
          color: kWhiteColor.withValues(alpha: 0.55),
        ),
      );
    }

    final col = column;
    if (col == null) {
      return _TextInput(
        value: rule.value ?? '',
        hint: 'Value',
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
      );
    }

    final enumValues = col.enumValues;
    if (!needsMultiple && enumValues != null && enumValues.isNotEmpty) {
      final currentValue = rule.value;
      return _Dropdown<String>(
        value:
            currentValue != null && enumValues.contains(currentValue)
                ? currentValue
                : null,
        hint: 'Select value',
        items: [for (final v in enumValues) _DropdownItem(value: v, label: v)],
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
      );
    }

    if (!needsMultiple) {
      final type = col.type;
      final hint = type == 'datetime' ? 'YYYY-MM-DD or ISO date' : 'Value';
      return _TextInput(
        value: rule.value ?? '',
        hint: hint,
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
        keyboardType: _keyboardTypeFor(type),
      );
    }

    final existing = rule.values ?? const [];
    final label = op == 'between' ? 'A,B' : 'A,B,C';
    return _TextInput(
      value: existing.join(','),
      hint: label,
      onChanged: (v) {
        final parts =
            v
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
        onChanged(rule.copyWith(values: parts, overrideValues: true));
      },
    );
  }

  TextInputType _keyboardTypeFor(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'integer':
      case 'number':
        return TextInputType.number;
      default:
        return TextInputType.text;
    }
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isActive ? kWhiteColor.withValues(alpha: 0.14) : kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                isActive
                    ? kWhiteColor.withValues(alpha: 0.35)
                    : kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: isActive ? kWhiteColor : kWhiteColor.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(values.length, (index) {
          final v = values[index];
          final selected = v == value;
          return GestureDetector(
            onTap: () => onChanged(v),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color:
                    selected
                        ? kWhiteColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                labels[index],
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      selected
                          ? kWhiteColor
                          : kWhiteColor.withValues(alpha: 0.75),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DropdownItem<T> {
  const _DropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final String? hint;
  final List<_DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kBlack2Color,
          iconEnabledColor: kWhiteColor.withValues(alpha: 0.7),
          hint:
              hint == null
                  ? null
                  : Text(
                    hint!,
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.55),
                    ),
                  ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item.value,
                child: Text(
                  item.label,
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.value,
    required this.hint,
    required this.onChanged,
    this.keyboardType,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
        ),
      ),
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  const _SmallTextButton({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        child: Text(
          label,
          style: AppTypography.textSmMedium.copyWith(
            color: color ?? kWhiteColor.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: kRedColor, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: AppTypography.textSmRegular.copyWith(color: kRedColor),
            ),
          ),
        ],
      ),
    );
  }
}

String _humanize(String name) {
  return name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (m) => '${m.group(1)} ${m.group(2)}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _operatorLabel(String op) {
  switch (op) {
    case 'eq':
      return 'Equals';
    case 'ne':
      return 'Not Equals';
    case 'lt':
      return 'Less Than';
    case 'lte':
      return 'Less or Equal';
    case 'gt':
      return 'Greater Than';
    case 'gte':
      return 'Greater or Equal';
    case 'in':
      return 'In List';
    case 'nin':
      return 'Not In List';
    case 'like':
      return 'Like';
    case 'ilike':
      return 'Like (CI)';
    case 'startsWith':
      return 'Starts With';
    case 'endsWith':
      return 'Ends With';
    case 'contains':
      return 'Contains';
    case 'notContains':
      return 'Not Contains';
    case 'between':
      return 'Between';
    case 'isNull':
      return 'Is Empty';
    case 'isNotNull':
      return 'Is Not Empty';
    default:
      return op;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isNotEmpty ? first : null;
}
