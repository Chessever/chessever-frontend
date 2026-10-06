import 'dart:async';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What the add dialog hands back: a display name and the accounts the
/// reader typed, each already confirmed to exist.
class PrepAddResult {
  const PrepAddResult(this.name, this.accounts);
  final String name;
  final List<PrepAccount> accounts;
}

/// Asks for Lichess and/or Chess.com usernames, checking each one as it is
/// typed. [kind] decides the wording; [only] limits it to one provider when
/// an account is being added to an existing profile.
Future<PrepAddResult?> showPrepAddAccountsDialog(
  BuildContext context, {
  required PrepKind kind,
  PrepSource? only,
  Set<String> existingKeys = const {},
}) {
  return showAlertModal<PrepAddResult>(
    context: context,
    child: _AddAccountsDialog(kind: kind, only: only, existingKeys: existingKeys),
  );
}

/// Renames a profile.
Future<String?> showPrepRenameDialog(BuildContext context, String current) {
  return showAlertModal<String>(
    context: context,
    child: _RenameDialog(current: current),
  );
}

/// The card every Prep dialog sits on, matching the Library's dialogs.
class PrepDialogCard extends StatelessWidget {
  const PrepDialogCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: ResponsiveHelper.isTablet ? 440 : double.infinity,
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(24.br),
          border: Border.all(color: context.colors.divider),
          boxShadow: [
            context.isLightTheme
                ? BoxShadow(
                    color: context.colors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                : BoxShadow(
                    color: context.colors.shadow,
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
          ],
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.sp),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10.sp),
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                    child: icon,
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.textLgBold.copyWith(
                            color: context.colors.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: 2.h),
                          Text(
                            subtitle!,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textSecondary,
                              height: 16 / 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 22.h),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Cancel and a primary action, as the Library's dialogs lay them out.
class PrepDialogActions extends StatelessWidget {
  const PrepDialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.busy = false,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 15.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: Text(
              'Cancel',
              style: AppTypography.textSmMedium.copyWith(
                color: context.textInk(0.55),
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.textPrimary,
              foregroundColor: context.colors.textInverse,
              disabledBackgroundColor: context.colors.textPrimary.withValues(
                alpha: 0.12,
              ),
              disabledForegroundColor: context.textInk(0.4),
              padding: EdgeInsets.symmetric(vertical: 15.h),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: busy
                ? SizedBox.square(
                    dimension: 16.sp,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textInverse,
                    ),
                  )
                : Text(confirmLabel, style: AppTypography.textSmBold),
          ),
        ),
      ],
    );
  }
}

/// A field label in the Library dialogs' style.
class PrepFieldLabel extends StatelessWidget {
  const PrepFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8.h),
    child: Text(
      text,
      style: AppTypography.textXsMedium.copyWith(color: context.textInk(0.55)),
    ),
  );
}

InputDecoration prepInputDecoration(
  BuildContext context, {
  required String hint,
  Widget? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.textMdRegular.copyWith(
      color: context.textInk(0.3),
    ),
    filled: true,
    fillColor: context.colors.textPrimary.withValues(alpha: 0.05),
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 15.h),
    counterText: '',
    prefixIcon: prefix,
    prefixIconConstraints: BoxConstraints(minWidth: 48.w),
    suffixIcon: suffix,
    suffixIconConstraints: BoxConstraints(minWidth: 44.w),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.br),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.br),
      borderSide: BorderSide(color: context.colors.accentText, width: 1.5),
    ),
  );
}

// ------------------------------------------------------------------ add

enum _Check { empty, checking, found, failed }

class _UsernameField {
  _UsernameField(this.source);

  final PrepSource source;
  final controller = TextEditingController();
  final focus = FocusNode();
  _Check state = _Check.empty;
  PrepAccount? account;
  String? error;
  Timer? debounce;
  int generation = 0;

  void dispose() {
    debounce?.cancel();
    controller.dispose();
    focus.dispose();
  }
}

class _AddAccountsDialog extends ConsumerStatefulWidget {
  const _AddAccountsDialog({
    required this.kind,
    required this.only,
    required this.existingKeys,
  });

  final PrepKind kind;
  final PrepSource? only;
  final Set<String> existingKeys;

  @override
  ConsumerState<_AddAccountsDialog> createState() => _AddAccountsDialogState();
}

class _AddAccountsDialogState extends ConsumerState<_AddAccountsDialog> {
  late final List<_UsernameField> _fields = [
    for (final source in widget.only == null ? PrepSource.values : [widget.only!])
      _UsernameField(source),
  ];
  final _name = TextEditingController();
  bool _nameEdited = false;

  bool get _opponent => widget.kind != PrepKind.mine && widget.only == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fields.first.focus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    _name.dispose();
    super.dispose();
  }

  void _changed(_UsernameField field) {
    field.debounce?.cancel();
    final text = field.controller.text.trim();
    final generation = ++field.generation;
    setState(() {
      field.account = null;
      field.error = null;
      field.state = text.isEmpty ? _Check.empty : _Check.checking;
    });
    if (text.isEmpty) return;
    field.debounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final account = await ref
            .read(prepRepositoryProvider)
            .lookup(field.source, text);
        if (!mounted || generation != field.generation) return;
        final owner = ref
            .read(prepProfilesProvider.notifier)
            .owning(account.source, account.username);
        if (widget.existingKeys.contains(account.key) ||
            (owner != null && owner.kind != PrepKind.favorite)) {
          setState(() {
            field.state = _Check.failed;
            field.error = owner == null
                ? 'Already added.'
                : 'Already in ${owner.kind == PrepKind.mine ? 'My games' : owner.name}.';
          });
          return;
        }
        setState(() {
          field.state = _Check.found;
          field.account = account;
          if (_opponent && !_nameEdited) {
            final suggestion = _suggestedName();
            if (suggestion != null) _name.text = suggestion;
          }
        });
      } on PrepException catch (e) {
        if (!mounted || generation != field.generation) return;
        setState(() {
          field.state = _Check.failed;
          field.error = e.message;
        });
      } catch (_) {
        if (!mounted || generation != field.generation) return;
        setState(() {
          field.state = _Check.failed;
          field.error = 'Could not check this name. Try again.';
        });
      }
    });
  }

  String? _suggestedName() {
    for (final f in _fields) {
      final a = f.account;
      if (a?.displayName != null) return a!.displayName;
    }
    for (final f in _fields) {
      if (f.account != null) return f.account!.username;
    }
    return null;
  }

  bool get _canAdd {
    final anyFound = _fields.any((f) => f.state == _Check.found);
    final noneBusyOrBad = _fields.every(
      (f) => f.state == _Check.found || f.state == _Check.empty,
    );
    return anyFound && noneBusyOrBad;
  }

  void _confirm() {
    if (!_canAdd) {
      HapticFeedbackService.light();
      return;
    }
    HapticFeedbackService.medium();
    final accounts = [
      for (final f in _fields)
        if (f.account != null) f.account!,
    ];
    final typed = _name.text.trim();
    Navigator.of(context).pop(
      PrepAddResult(
        typed.isNotEmpty ? typed : (_suggestedName() ?? accounts.first.username),
        accounts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final only = widget.only;
    final title = only != null
        ? 'Add ${only.label} account'
        : widget.kind == PrepKind.mine
        ? 'Add your accounts'
        : 'Add an opponent';
    final subtitle = only != null
        ? null
        : widget.kind == PrepKind.mine
        ? 'Your games stay up to date three times a day.'
        : 'Enter one or both of their usernames.';
    return PrepDialogCard(
      icon: Icon(
        widget.kind == PrepKind.mine
            ? Icons.person_rounded
            : Icons.person_search_rounded,
        color: context.colors.textPrimary,
        size: 22.sp,
      ),
      title: title,
      subtitle: subtitle,
      children: [
        for (final field in _fields) ...[
          _usernameField(field),
          SizedBox(height: 16.h),
        ],
        if (_opponent) ...[
          const PrepFieldLabel('Name'),
          TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _nameEdited = true,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
            cursorColor: context.colors.accentText,
            decoration: prepInputDecoration(
              context,
              hint: 'Filled in from their profile',
            ),
          ),
          SizedBox(height: 8.h),
        ],
        SizedBox(height: 16.h),
        PrepDialogActions(
          confirmLabel: 'Add',
          onConfirm: _canAdd ? _confirm : null,
        ),
      ],
    );
  }

  Widget _usernameField(_UsernameField field) {
    final colors = context.colors;
    final status = switch (field.state) {
      _Check.empty => null,
      _Check.checking => SizedBox.square(
        dimension: 16.sp,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.textSecondary,
        ),
      ),
      _Check.found => Icon(
        Icons.check_circle_rounded,
        size: 20.sp,
        color: colors.successStrong,
      ),
      _Check.failed => Icon(
        Icons.error_rounded,
        size: 20.sp,
        color: colors.danger,
      ),
    };
    final found = field.account;
    final caption = switch (field.state) {
      _Check.found when found != null => [
        if (found.title != null) found.title!,
        if (found.displayName != null) found.displayName!,
        if (found.bestRating != null) '${found.bestRating}',
      ].join(' · '),
      _Check.failed => field.error,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrepFieldLabel('${field.source.label} username'),
        TextField(
          controller: field.controller,
          focusNode: field.focus,
          maxLength: 60,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: field == _fields.last && !_opponent
              ? TextInputAction.done
              : TextInputAction.next,
          onChanged: (_) => _changed(field),
          onSubmitted: (_) {
            final next = _fields.indexOf(field) + 1;
            if (next < _fields.length) {
              _fields[next].focus.requestFocus();
            } else if (!_opponent) {
              _confirm();
            }
          },
          style: AppTypography.textMdMedium.copyWith(color: colors.textPrimary),
          cursorColor: colors.accentText,
          decoration: prepInputDecoration(
            context,
            hint: field.source == PrepSource.lichess
                ? 'e.g. DrNykterstein'
                : 'e.g. MagnusCarlsen',
            prefix: Padding(
              padding: EdgeInsets.only(left: 12.w, right: 10.w),
              child: PrepSourceMark(source: field.source, size: 24.sp),
            ),
            suffix: status == null
                ? null
                : Padding(
                    padding: EdgeInsets.only(right: 12.w),
                    child: status,
                  ),
          ),
        ),
        // Reserved so the dialog does not jump as checks come and go.
        SizedBox(
          height: 22.h,
          child: Padding(
            padding: EdgeInsets.only(top: 6.h, left: 2.w),
            child: Text(
              caption ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsRegular.copyWith(
                color: field.state == _Check.failed
                    ? colors.danger
                    : colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ rename

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});
  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    HapticFeedbackService.medium();
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return PrepDialogCard(
      icon: Icon(
        Icons.edit_rounded,
        color: context.colors.textPrimary,
        size: 22.sp,
      ),
      title: 'Rename',
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _save(),
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
          ),
          cursorColor: context.colors.accentText,
          decoration: prepInputDecoration(context, hint: 'Name'),
        ),
        SizedBox(height: 24.h),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => PrepDialogActions(
            confirmLabel: 'Save',
            onConfirm: _controller.text.trim().isEmpty ? null : _save,
          ),
        ),
      ],
    );
  }
}
