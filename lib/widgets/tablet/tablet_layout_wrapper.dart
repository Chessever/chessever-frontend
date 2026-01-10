import 'package:flutter/material.dart';
import 'package:chessever2/utils/responsive_helper.dart';

/// A wrapper that constrains content width on tablets for better readability.
/// On phones, it passes through the child unchanged.
class TabletContentContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool center;

  const TabletContentContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveHelper.isTablet) {
      return child;
    }

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? ResponsiveHelper.contentMaxWidth,
      ),
      child: child,
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (center) {
      return Center(child: content);
    }

    return content;
  }
}

/// A split-view layout for master-detail patterns on tablets.
/// Shows side-by-side panels in landscape, stacked in portrait.
/// On phones, only shows the master or detail based on selection state.
class TabletSplitView extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final int masterFlex;
  final int detailFlex;
  final bool showDivider;
  final Color? dividerColor;

  const TabletSplitView({
    super.key,
    required this.master,
    required this.detail,
    this.masterFlex = 2,
    this.detailFlex = 3,
    this.showDivider = true,
    this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveHelper.shouldUseSplitView) {
      // On phones or tablet portrait, show only master
      // (Detail should be pushed as a new route)
      return master;
    }

    return Row(
      children: [
        Expanded(flex: masterFlex, child: master),
        if (showDivider)
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: dividerColor ?? Theme.of(context).dividerColor,
          ),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}

/// A responsive grid that adjusts column count based on device and orientation.
class TabletResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int phoneColumns;
  final double spacing;
  final double runSpacing;
  final EdgeInsetsGeometry? padding;

  const TabletResponsiveGrid({
    super.key,
    required this.children,
    this.phoneColumns = 1,
    this.spacing = 16,
    this.runSpacing = 16,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: phoneColumns,
    );

    Widget grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: runSpacing,
        childAspectRatio: 1.0,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );

    if (padding != null) {
      grid = Padding(padding: padding!, child: grid);
    }

    return TabletContentContainer(child: grid);
  }
}

/// A sliver version of the responsive grid for use in CustomScrollView.
class TabletResponsiveSliverGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final int phoneColumns;
  final double spacing;
  final double runSpacing;
  final double childAspectRatio;

  const TabletResponsiveSliverGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.phoneColumns = 1,
    this.spacing = 16,
    this.runSpacing = 16,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: phoneColumns,
    );

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: runSpacing,
        childAspectRatio: childAspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
    );
  }
}

/// A wrapper that applies tablet-specific padding.
class TabletPadding extends StatelessWidget {
  final Widget child;
  final double phoneHorizontal;
  final double phoneVertical;
  final double? tabletHorizontal;
  final double? tabletVertical;

  const TabletPadding({
    super.key,
    required this.child,
    this.phoneHorizontal = 16,
    this.phoneVertical = 0,
    this.tabletHorizontal,
    this.tabletVertical,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = ResponsiveHelper.adaptive(
      phone: phoneHorizontal,
      tablet: tabletHorizontal ?? phoneHorizontal * 1.5,
    );

    final vertical = ResponsiveHelper.adaptive(
      phone: phoneVertical,
      tablet: tabletVertical ?? phoneVertical,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      child: child,
    );
  }
}

/// A card that adapts its size and layout for tablets.
class TabletAdaptiveCard extends StatelessWidget {
  final Widget child;
  final double? phoneWidth;
  final double? tabletWidth;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? elevation;
  final BorderRadius? borderRadius;

  const TabletAdaptiveCard({
    super.key,
    required this.child,
    this.phoneWidth,
    this.tabletWidth,
    this.padding,
    this.color,
    this.elevation,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final width = ResponsiveHelper.adaptive(
      phone: phoneWidth ?? double.infinity,
      tablet: tabletWidth ?? ResponsiveHelper.getCardWidth(),
    );

    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).cardColor,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        boxShadow:
            elevation != null
                ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: elevation!,
                    offset: Offset(0, elevation! / 2),
                  ),
                ]
                : null,
      ),
      child: child,
    );
  }
}

/// Extension to easily wrap any widget with tablet container
extension TabletLayoutExtension on Widget {
  Widget withTabletContainer({double? maxWidth, bool center = true}) {
    return TabletContentContainer(
      maxWidth: maxWidth,
      center: center,
      child: this,
    );
  }

  Widget withTabletPadding({
    double phoneHorizontal = 16,
    double? tabletHorizontal,
  }) {
    return TabletPadding(
      phoneHorizontal: phoneHorizontal,
      tabletHorizontal: tabletHorizontal,
      child: this,
    );
  }
}
