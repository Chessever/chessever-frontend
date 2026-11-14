import 'dart:async';
import 'dart:io';

import 'package:chessever2/services/forced_update_policy.dart';
import 'package:chessever2/services/phone_update_reminder.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/phone_update_route_observer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Custom upgrade messages for localization support
class CustomUpgraderMessages extends UpgraderMessages {
  @override
  String get title => 'Update Available';

  @override
  String get body =>
      'A new version of ChessEver is available. Update now to get the latest features and improvements.';

  @override
  String get buttonTitleIgnore => 'Skip This Version';

  @override
  String get buttonTitleLater => 'Remind me in 3 days';

  @override
  String get buttonTitleUpdate => 'Update Now';

  @override
  String get prompt => '';

  /// Replace [title] and [body] while the update is mandatory.
  static const requiredTitle = 'Update Required';
  static const requiredBody =
      'This version of ChessEver is no longer supported. '
      'Update to keep using the app.';
}

/// Store updates only. Checks are armed on launch/resume, not every rebuild.
///
/// An update is mandatory when Upgrader's `blocked()` says so (install below
/// `minAppVersion`, which [policySource] sets remotely over the store
/// listing's tag, or a critical flag) or when the store offers a new major
/// version and the policy enforces those. See [requiresMajorUpdate].
class CustomUpgradeAlert extends StatefulWidget {
  final Widget child;
  final Upgrader upgrader;
  final GlobalKey<NavigatorState> navigatorKey;
  final PhoneUpdateRouteObserver routeObserver;
  final PhoneUpdateReminder? reminder;
  final bool? enabled;

  /// Remote rules for mandatory updates. Defaults to
  /// [ForcedUpdatePolicy.fallback], which never touches Firebase.
  final ForcedUpdatePolicySource? policySource;

  const CustomUpgradeAlert({
    super.key,
    required this.child,
    required this.upgrader,
    required this.navigatorKey,
    required this.routeObserver,
    this.reminder,
    this.enabled,
    this.policySource,
  });

  @override
  CustomUpgradeAlertState createState() => CustomUpgradeAlertState();
}

class CustomUpgradeAlertState extends State<CustomUpgradeAlert>
    with WidgetsBindingObserver {
  late final PhoneUpdateReminder _reminder;
  late final ForcedUpdatePolicySource _policySource;
  StreamSubscription<void>? _policyChanges;
  ForcedUpdatePolicy _policy = ForcedUpdatePolicy.fallback;

  /// The open dialog's mandatory flag. Remote Config can flip it while the
  /// dialog is up: on to lock an optional offer, off as an emergency release.
  final _dialogMandatory = ValueNotifier<bool>(false);

  /// The store version the open dialog offers; null while none is open.
  String? _dialogOffered;

  /// A policy change landed mid-check, after that check read the policy.
  bool _policyRecheck = false;
  bool _entryArmed = true;
  bool _manualPending = false;
  bool _busy = false;
  bool _initialized = false;
  bool _scheduled = false;
  int _generation = 0;
  int? _checkedGeneration;

  bool get _enabled =>
      widget.enabled ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _safe => _foreground && widget.routeObserver.isSafe;

  @override
  void initState() {
    super.initState();
    _reminder = widget.reminder ?? PhoneUpdateReminder();
    _policySource =
        widget.policySource ?? const FixedForcedUpdatePolicySource();
    WidgetsBinding.instance.addObserver(this);
    widget.routeObserver.safeToPrompt.addListener(_schedule);
    if (_enabled) {
      _policyChanges = _policySource.changes.listen(
        (_) => _onPolicyChanged(),
        onError: (Object _) {
          debugPrint('[ForcedUpdate] Remote Config updates unavailable.');
        },
      );
    }
    _schedule();
  }

  @override
  void dispose() {
    unawaited(_policyChanges?.cancel());
    widget.routeObserver.safeToPrompt.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    widget.upgrader.dispose();
    _dialogMandatory.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _generation++;
    if (state == AppLifecycleState.resumed) {
      _entryArmed = true;
      _schedule();
      // An open dialog holds the check, so re-read only the policy for it.
      unawaited(_refreshOpenDialog());
    }
  }

  Future<ForcedUpdatePolicy> _loadPolicy() =>
      _policySource.load().catchError((Object _) => _policy);

  void _applyPolicy(ForcedUpdatePolicy policy) {
    _policy = policy;
    applyMinAppVersion(widget.upgrader, policy);
  }

  /// Display is still gated on the store offering something newer than the
  /// install ([PhoneUpdateReminder.shouldOffer]), so neither rule can lock
  /// anyone out of the app when there is nothing to install.
  bool _isMandatory(String? offered) =>
      widget.upgrader.blocked() ||
      requiresMajorUpdate(
        installedVersion: widget.upgrader.currentInstalledVersion,
        offeredVersion: offered,
        policy: _policy,
      );

  /// A new minimum, or an emergency release, reaches people already in the
  /// app, not only at launch. The store result is reused, not re-queried.
  void _onPolicyChanged() {
    if (!mounted) return;
    if (_dialogOffered != null) {
      unawaited(_refreshOpenDialog());
    } else if (_busy) {
      // The running check may have read the old policy; run it again after.
      _policyRecheck = true;
    } else {
      _entryArmed = true;
      _schedule();
    }
  }

  Future<void> _refreshOpenDialog() async {
    if (_dialogOffered == null) return;
    final policy = await _loadPolicy();
    if (!mounted) return;
    _applyPolicy(policy);
    final offered = _dialogOffered;
    if (offered != null) _dialogMandatory.value = _isMandatory(offered);
  }

  /// Explicit checks bypass the snooze, but still wait for a safe route.
  /// No existing settings/store action is rerouted through an automatic gate.
  void checkForUpdate({bool manual = false}) {
    if (!_busy) _checkedGeneration = null;
    _entryArmed = true;
    _manualPending = _manualPending || manual;
    _schedule();
  }

  void _schedule() {
    if (!mounted || !_enabled || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_evaluate());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _evaluate() async {
    if (!mounted || !_enabled || _busy || !_entryArmed || !_safe) return;
    final generation = _generation;
    _busy = true;
    var retry = false;
    try {
      // Fetched in parallel with the store check; a failure keeps the last.
      final policy = _loadPolicy();
      if (_checkedGeneration != generation) {
        if (!_initialized) {
          await widget.upgrader.initialize();
          _initialized = true;
        } else {
          await widget.upgrader.updateVersionInfo();
        }
        // Navigation can temporarily make a completed check unsafe to show.
        // Reuse this entry's result on the safe route instead of re-querying.
        _checkedGeneration = generation;
      }
      _applyPolicy(await policy);
      // Upgrader registers itself after async initialization. Clean it up even
      // if the shell was disposed before that future completed.
      if (!mounted) {
        widget.upgrader.dispose();
        return;
      }
      final offered = widget.upgrader.currentAppStoreVersion;
      final mandatory = _isMandatory(offered);
      final manual = _manualPending;
      final shouldOffer = await _reminder.shouldOffer(
        installedVersion: widget.upgrader.currentInstalledVersion,
        offeredVersion: offered,
        mandatory: mandatory,
        manual: manual,
      );
      if (!mounted || generation != _generation || !_safe) return;
      _entryArmed = false;
      _manualPending = false;
      if (!shouldOffer ||
          offered == null ||
          (!mandatory &&
              !manual &&
              widget.upgrader.alreadyIgnoredThisVersion())) {
        return;
      }
      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;
      final messages = widget.upgrader.determineMessages(navigatorContext);
      final theme = _dialogTheme(context);
      _dialogMandatory.value = mandatory;
      _dialogOffered = offered;
      if (_policyRecheck) {
        // A change landed after this check read the policy. Waiting for the
        // dialog to close would never come if it opened locked.
        _policyRecheck = false;
        unawaited(_refreshOpenDialog());
      }
      final _UpdateChoice? choice;
      try {
        choice = await showDialog<_UpdateChoice>(
          context: navigatorContext,
          // A mandatory dialog's PopScope also refuses barrier taps, which
          // covers an optional offer that Remote Config locks while open.
          barrierDismissible: !mandatory,
          builder: (dialogContext) => Theme(
            data: theme,
            child: _PhoneStoreUpdateDialog(
              upgrader: widget.upgrader,
              reminder: _reminder,
              offeredVersion: offered,
              mandatory: _dialogMandatory,
              messages: messages,
            ),
          ),
        );
      } finally {
        _dialogOffered = null;
      }
      // No button closes a mandatory dialog, so null means navigation removed
      // it: a deep link or sign-out clearing the stack. Show it again on the
      // next safe route, reusing this store result.
      final removed = choice == null && _dialogMandatory.value;
      // Dismissing an optional offer (outside tap, back) is a "later" too.
      // Without this it would return on every safe resume, with no cooldown.
      if (choice == null && !removed) {
        await _reminder.snooze(offered);
      }
      // Resumes while a dialog is already open are satisfied by that dialog.
      _entryArmed = removed;
      retry = removed;
      _manualPending = false;
    } catch (_) {
      // Failure is not an update offer. Retry on the next launch/resume or
      // explicit check, rather than spinning on every navigation/rebuild.
      if (generation == _generation) _entryArmed = false;
    } finally {
      _busy = false;
      if (_policyRecheck) {
        _policyRecheck = false;
        _entryArmed = true;
        retry = true;
      }
      if (mounted && _entryArmed && (retry || generation != _generation)) {
        _schedule();
      }
    }
  }

  ThemeData _dialogTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: context.colors.popup,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.sp),
        ),
        titleTextStyle: AppTypography.textXlBold.copyWith(
          color: context.colors.textPrimary,
        ),
        contentTextStyle: AppTypography.textSmRegular.copyWith(
          color: context.colors.textPrimaryMuted,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: context.colors.textPrimary,
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.sp),
          ),
          textStyle: AppTypography.textMdMedium,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: context.colors.textPrimary,
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.sp),
          ),
          textStyle: AppTypography.textMdBold,
          elevation: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(data: _dialogTheme(context), child: widget.child);
  }
}

/// How the dialog was closed; null when it was dismissed.
enum _UpdateChoice { later, update }

class _PhoneStoreUpdateDialog extends StatefulWidget {
  const _PhoneStoreUpdateDialog({
    required this.upgrader,
    required this.reminder,
    required this.offeredVersion,
    required this.mandatory,
    required this.messages,
  });

  final Upgrader upgrader;
  final PhoneUpdateReminder reminder;
  final String offeredVersion;

  /// Live: Remote Config can lock or release the dialog while it is open.
  final ValueListenable<bool> mandatory;
  final UpgraderMessages messages;

  @override
  State<_PhoneStoreUpdateDialog> createState() =>
      _PhoneStoreUpdateDialogState();
}

class _PhoneStoreUpdateDialogState extends State<_PhoneStoreUpdateDialog> {
  bool _acting = false;
  String? _error;

  void _closeDialog(_UpdateChoice choice) {
    final route = ModalRoute.of<_UpdateChoice>(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(choice);
    } else {
      // A deep link can push a game while a preference/store future is pending.
      // Remove this exact dialog, never pop the newly opened game above it.
      navigator.removeRoute(route, choice);
    }
  }

  Future<void> _later() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final saved = await widget.reminder.snooze(widget.offeredVersion);
      if (!mounted) return;
      if (saved) {
        _closeDialog(_UpdateChoice.later);
      } else {
        setState(() => _error = 'Could not save reminder. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save reminder. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _update() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      // Keep Upgrader's existing platform-specific store launch contract.
      await widget.upgrader.sendUserToAppStore();
      if (mounted && !widget.mandatory.value) {
        _closeDialog(_UpdateChoice.update);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open update. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.mandatory,
      builder: (context, mandatory, _) => _buildDialog(context, mandatory),
    );
  }

  Widget _buildDialog(BuildContext context, bool mandatory) {
    final messages = widget.messages;
    final cupertino = !kIsWeb && Platform.isIOS;
    final notes = widget.upgrader.releaseNotes;
    Widget button(String label, VoidCallback action) => cupertino
        ? CupertinoDialogAction(
            onPressed: _acting ? null : action,
            textStyle: AppTypography.textMdMedium.copyWith(
              color: context.colors.accentText,
            ),
            child: Text(label),
          )
        : TextButton(onPressed: _acting ? null : action, child: Text(label));
    final title = Text(
      mandatory ? CustomUpgraderMessages.requiredTitle : messages.title,
      key: const Key('upgrader.dialog.title'),
    );
    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mandatory
                ? CustomUpgraderMessages.requiredBody
                : widget.upgrader.body(messages),
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 15),
            Text(messages.message(UpgraderMessage.releaseNotes) ?? ''),
            Text(notes),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
        ],
      ),
    );
    final actions = [
      if (!mandatory) button(messages.buttonTitleLater, _later),
      button(messages.buttonTitleUpdate, _update),
    ];
    return PopScope(
      canPop: !mandatory && !_acting,
      child: cupertino
          ? CupertinoAlertDialog(
              title: title,
              content: content,
              actions: actions,
            )
          : AlertDialog(title: title, content: content, actions: actions),
    );
  }
}
