import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const kLogoAsset = 'assets/pngs/chessever-mark.png';
const kPrivacyUrl = 'https://chessever.com/privacy-policy';
const kTermsUrl = 'https://chessever.com/terms-of-use';

TextStyle _inter({
  double? fontSize,
  double? height,
  Color? color,
  FontWeight? fontWeight,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'InterDisplay',
  fontSize: fontSize,
  height: height,
  color: color,
  fontWeight: fontWeight,
  letterSpacing: letterSpacing,
);

enum PaywallTrigger { settings, favorites, database }

enum PlanType { monthly, annual }

// ----------------------------------------------------------------------------
// Copy — the only thing that changes per trigger.
// ----------------------------------------------------------------------------
class _Copy {
  const _Copy(this.line1, this.line2, this.sub);
  final String line1; // regular
  final String line2; // italic, tinted
  final String sub;

  static _Copy forTrigger(PaywallTrigger t) {
    switch (t) {
      case PaywallTrigger.settings:
        return const _Copy(
          'Your chess.',
          'Without limits.',
          'More of what matters. No interruptions.',
        );
      case PaywallTrigger.favorites:
        return const _Copy(
          'Follow every player',
          'you care about.',
          "You've used your free favorites. Premium has no limit.",
        );
      case PaywallTrigger.database:
        return const _Copy(
          'Keep every game',
          'you play.',
          "You've used your free database slots. Premium has no limit.",
        );
    }
  }
}

// ----------------------------------------------------------------------------
// Colors (PAYWALL_SPEC.md §3)
// ----------------------------------------------------------------------------
class _C {
  static const bg = Color(0xFF0B0D11);
  static const textPrimary = Color(0xFFF2F5F8);
  static const textSecondary = Color(0xFF8B95A3);
  static const textTertiary = Color(0xFFAEB7C2);
  static const icon = Color(0xFFC9D1DB);
  static const accent = Color(0xFF12B1E4);
  static const accentInk = Color(0xFF031A22);
  static const headlineItalic = Color(0xFFCFE9F2);
  static const border = Color(0xFF232932);
  static const divider = Color(0xFF3A414B);
  static const handle = Color(0xFF30363F);
  static const radioInset = Color(0xFF0E1A20);
}

class PremiumPaywallView extends StatelessWidget {
  const PremiumPaywallView({
    super.key,
    this.trigger = PaywallTrigger.settings,
    required this.plan,
    required this.annual,
    required this.monthly,
    required this.busy,
    required this.loadingProducts,
    this.error,
    this.productsError,
    required this.onSelect,
    required this.onPurchase,
    required this.onRestore,
    required this.onRedeem,
    required this.onClose,
    required this.onRetry,
    required this.onOpenUrl,
    this.pricingOnly = false,
  });
  final PaywallTrigger trigger;
  final PlanType plan;
  final Package? annual, monthly;
  final bool busy, loadingProducts, pricingOnly;
  final String? error, productsError;
  final ValueChanged<PlanType> onSelect;
  final VoidCallback onPurchase, onRestore, onRedeem, onClose, onRetry;
  final ValueChanged<String> onOpenUrl;
  PlanType get _plan => plan;
  Package? get _annual => annual;
  Package? get _monthly => monthly;
  Package? get _selected => plan == PlanType.annual ? annual : monthly;
  bool get _purchasing => busy;
  bool get _loadingOffer => loadingProducts;
  String? get _error => error;
  void _purchase() => onPurchase();
  void _restore() => onRestore();
  void _redeemCode() => onRedeem();
  void _open(String url) => onOpenUrl(url);
  // "$10.00" — annual price / 12 in the product's currency.
  String? get _annualPerMonth {
    final p = _annual?.storeProduct;
    if (p == null) return null;
    final f = NumberFormat.simpleCurrency(name: p.currencyCode);
    return f.format(p.price / 12);
  }

  // "SAVE 17%" — hidden if it would be 0 or negative.
  String? get _saveBadge {
    final a = _annual?.storeProduct.price;
    final m = _monthly?.storeProduct.price;
    if (a == null || m == null || m <= 0) return null;
    final pct = ((1 - a / (m * 12)) * 100).round();
    return pct > 0 ? 'SAVE $pct%' : null;
  }

  String get _renewLine {
    final price = _selected?.storeProduct.priceString;
    if (price == null) return 'Cancel anytime in your store settings.';
    final per = _plan == PlanType.annual ? 'year' : 'month';
    return 'Renews at $price/$per until canceled. Cancel anytime in your store settings.';
  }

  @override
  Widget build(BuildContext context) {
    final copy = _Copy.forTrigger(trigger);

    if (pricingOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _annualRow(_annual?.storeProduct.priceString ?? "—"),
          const SizedBox(height: 8),
          _monthlyRow(_monthly?.storeProduct.priceString ?? "—"),
        ],
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: _C.bg,
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              _hero(),
                              const SizedBox(height: 8),
                              _headline(copy),
                              const SizedBox(height: 10),
                              Text(
                                copy.sub,
                                textAlign: TextAlign.center,
                                style: _inter(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: _C.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 36),
                              _benefits(),
                              const SizedBox(height: 48),
                            ],
                          ),
                        ),
                        // Hint that the benefits continue beneath checkout.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 48,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [_C.bg.withValues(alpha: 0), _C.bg],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Checkout stays pinned, but in a short window (folded Duo in
                  // landscape) with larger text it may not take the whole sheet:
                  // past 70% of the height it scrolls within itself.
                  Builder(
                    builder: (context) => ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                      ),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: _bottom(),
                      ),
                    ),
                  ),
                ],
              ),
              _handle(),
              _closeButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() => Positioned(
    top: 10,
    left: 0,
    right: 0,
    child: Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: _C.handle,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ),
  );

  Widget _closeButton() => Positioned(
    top: 22,
    right: 18,
    child: Semantics(
      button: true,
      label: 'Close',
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            onClose();
          },
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close, size: 18, color: _C.textTertiary),
          ),
        ),
      ),
    ),
  );

  Widget _hero() => SizedBox(
    height: 160,
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.4),
                radius: 0.6,
                colors: [
                  _C.accent.withValues(alpha: 0.16),
                  _C.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Image.asset(kLogoAsset, width: 76, height: 76),
        ),
      ],
    ),
  );

  Widget _headline(_Copy copy) {
    const base = TextStyle(
      fontFamily: 'InstrumentSerif',
      fontSize: 42,
      height: 1.0,
      letterSpacing: -0.42,
      color: _C.textPrimary,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${copy.line1}\n', style: base),
          TextSpan(
            text: copy.line2,
            style: base.copyWith(
              fontStyle: FontStyle.italic,
              color: _C.headlineItalic,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _benefits() {
    const rows = [
      (
        _AdOffIcon(),
        'Ad-free experience',
        'Enjoy chess without interruptions.',
      ),
      (
        Icon(Icons.favorite_border, size: 20, color: _C.icon),
        'Unlimited favorites',
        'Follow every player you care about.',
      ),
      (
        Icon(Icons.storage_outlined, size: 20, color: _C.icon),
        'Database storage',
        'Organize your games and preparation.',
      ),
      (
        Icon(Icons.desktop_windows_outlined, size: 20, color: _C.icon),
        'Full web & desktop access',
        'Your Premium experience, beyond mobile.',
      ),
      (
        Icon(Icons.person_search_outlined, size: 20, color: _C.icon),
        'Opponent preparation',
        'Study player statistics, games, and opening tendencies.',
      ),
      (
        Icon(Icons.analytics_outlined, size: 20, color: _C.icon),
        'Detailed game reports',
        'Review your games and understand where you can improve.',
      ),
      (
        Icon(Icons.explore_outlined, size: 20, color: _C.icon),
        'Deeper opening exploration',
        'Explore positions beyond the free opening-depth limit.',
      ),
      (
        Icon(Icons.account_tree_outlined, size: 20, color: _C.icon),
        'Build opening trees',
        'Discover patterns across your databases, collections, and Prep games.',
      ),
      (
        Icon(Icons.file_copy_outlined, size: 20, color: _C.icon),
        'PGN import & copy',
        'Bring games into ChessEver and copy PGNs for use elsewhere.',
      ),
      (
        Icon(Icons.people_outline, size: 20, color: _C.icon),
        'Unlimited Prep profiles',
        'Add more opponents and connect more of your own accounts.',
      ),
      (
        Icon(Icons.dashboard_customize_outlined, size: 20, color: _C.icon),
        'Personalized home screen',
        'Customize your home screen around what matters to you.',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          for (final (icon, title, body) in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: _C.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        body,
                        style: _inter(
                          fontSize: 13,
                          height: 1.35,
                          color: _C.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (title != rows.last.$2) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _bottom() {
    final annualPrice = _annual?.storeProduct.priceString ?? '—';
    final monthlyPrice = _monthly?.storeProduct.priceString ?? '—';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (productsError != null) ...[
            Text(
              productsError!,
              style: _inter(fontSize: 12, color: _C.textSecondary),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: _loadingOffer ? null : onRetry,
              child: const Text("Retry"),
            ),
          ],
          _annualRow(annualPrice),
          const SizedBox(height: 8),
          _monthlyRow(monthlyPrice),
          const SizedBox(height: 12),
          _cta(),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: _inter(fontSize: 12, color: _C.textTertiary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _renewLine,
            textAlign: TextAlign.center,
            style: _inter(fontSize: 11, height: 1.4, color: _C.textSecondary),
          ),
          _legal(),
        ],
      ),
    );
  }

  Widget _annualRow(String price) {
    final on = _plan == PlanType.annual;
    final badge = _saveBadge;
    return _planShell(
      selected: on,
      onTap: () => _select(PlanType.annual),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _radio(on),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Annual',
                      style: _inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _C.textPrimary,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _C.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: _inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: _C.accentInk,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _annualPerMonth ?? '—',
                        style: _inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _C.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: '/mo',
                        style: _inter(fontSize: 12, color: _C.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: _inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: _C.textPrimary,
                ),
              ),
              Text(
                'per year',
                style: _inter(fontSize: 12, color: _C.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthlyRow(String price) {
    final on = _plan == PlanType.monthly;
    return _planShell(
      selected: on,
      onTap: () => _select(PlanType.monthly),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _radio(on),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Monthly',
              style: _inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _C.icon,
              ),
            ),
          ),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$price ',
                    style: _inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: 'per month',
                    style: _inter(fontSize: 12, color: _C.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planShell({
    required bool selected,
    required VoidCallback onTap,
    required EdgeInsets padding,
    required Widget child,
  }) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? _C.accent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.02),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? _C.accent : _C.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _purchasing || _loadingOffer ? null : onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Widget _radio(bool on) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? _C.accent : Colors.transparent,
      border: Border.all(color: on ? _C.accent : _C.divider, width: 1.5),
    ),
    child: on
        ? Center(
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _C.accent,
              ),
              foregroundDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _C.radioInset, width: 3),
              ),
            ),
          )
        : null,
  );

  void _select(PlanType p) {
    onSelect(p);
  }

  Widget _cta() {
    final enabled = _selected != null && !_purchasing && !_loadingOffer;
    return Opacity(
      opacity: enabled || _purchasing ? 1 : 0.4,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3CC4EE), _C.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: _C.accent.withValues(alpha: 0.22),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: enabled ? _purchase : null,
            child: Center(
              child: _purchasing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _C.accentInk,
                      ),
                    )
                  : Text(
                      'Get Premium',
                      style: _inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _C.accentInk,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legal() {
    Widget link(String label, VoidCallback onTap) => InkWell(
      onTap: _purchasing ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
        child: Text(
          label,
          style: _inter(fontSize: 11, color: _C.textSecondary),
        ),
      ),
    );
    const dot = Text('·', style: TextStyle(fontSize: 11, color: _C.divider));
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('Restore purchases', _restore),
        dot,
        link('Have a code?', _redeemCode),
        dot,
        link('Privacy', () => _open(kPrivacyUrl)),
        dot,
        link('Terms', () => _open(kTermsUrl)),
      ],
    );
  }
}

// Ad-off icon: rectangle with a diagonal slash (no Material equivalent).
class _AdOffIcon extends StatelessWidget {
  const _AdOffIcon();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(20, 20), painter: _AdOffPainter());
}

class _AdOffPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _C.icon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final s = size.width / 24;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * s, 5 * s, 18 * s, 14 * s),
        Radius.circular(2 * s),
      ),
      p,
    );
    canvas.drawLine(Offset(4 * s, 20 * s), Offset(20 * s, 4 * s), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
