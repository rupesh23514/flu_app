import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';
import '../../core/constants/app_colors.dart';

/// A scalable card widget that adapts to content and prevents overflow
class ScalableCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final double? elevation;
  final VoidCallback? onTap;

  const ScalableCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: elevation ?? 1,
      color: color,
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: ResponsiveUtils.borderRadius(context, 12),
      ),
      child: Padding(
        padding: padding ?? ResponsiveUtils.paddingAll(context, 12),
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: ResponsiveUtils.borderRadius(context, 12),
        child: card,
      );
    }

    return card;
  }
}

/// A scalable text widget that automatically scales and handles overflow
class ScalableText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool scalable;

  const ScalableText(
    this.text, {
    super.key,
    this.fontSize,
    this.fontWeight,
    this.color,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.scalable = true,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        fontSize: scalable
            ? ResponsiveUtils.fontSize(context, fontSize ?? 14)
            : fontSize ?? 14,
        fontWeight: fontWeight,
        color: color,
      ),
    );

    if (scalable && maxLines == 1) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: textAlign == TextAlign.right
            ? Alignment.centerRight
            : textAlign == TextAlign.center
                ? Alignment.center
                : Alignment.centerLeft,
        child: textWidget,
      );
    }

    return textWidget;
  }
}

/// A scalable amount display widget for currency values
class ScalableAmount extends StatelessWidget {
  final String amount;
  final double fontSize;
  final Color? color;
  final FontWeight fontWeight;
  final String? label;
  final double? labelFontSize;

  const ScalableAmount({
    super.key,
    required this.amount,
    this.fontSize = 18,
    this.color,
    this.fontWeight = FontWeight.bold,
    this.label,
    this.labelFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, labelFontSize ?? 12),
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: ResponsiveUtils.spacing(context, 4)),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, fontSize),
              fontWeight: fontWeight,
              color: color ?? AppColors.primary,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

/// A scalable row that wraps to column on small screens if needed
class ScalableRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final bool wrapOnSmallScreen;
  final double wrapThreshold;

  const ScalableRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing = 8,
    this.wrapOnSmallScreen = false,
    this.wrapThreshold = 360,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = ResponsiveUtils.screenWidth(context);
    
    if (wrapOnSmallScreen && screenWidth < wrapThreshold) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children.map((child) {
          return Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: child,
          );
        }).toList(),
      );
    }

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: _buildRowChildren(),
    );
  }

  List<Widget> _buildRowChildren() {
    final List<Widget> result = [];
    for (int i = 0; i < children.length; i++) {
      result.add(Flexible(child: children[i]));
      if (i < children.length - 1) {
        result.add(SizedBox(width: spacing));
      }
    }
    return result;
  }
}

/// A scalable info item (label + value) widget
class ScalableInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final double? valueFontSize;
  final CrossAxisAlignment alignment;

  const ScalableInfoItem({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.valueFontSize,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        if (icon != null)
          Icon(
            icon,
            size: ResponsiveUtils.iconSize(context, 20),
            color: AppColors.textSecondary,
          ),
        if (icon != null) SizedBox(height: ResponsiveUtils.spacing(context, 4)),
        Text(
          label,
          style: TextStyle(
            fontSize: ResponsiveUtils.fontSize(context, 11),
            color: AppColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: ResponsiveUtils.spacing(context, 2)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment == CrossAxisAlignment.end
              ? Alignment.centerRight
              : alignment == CrossAxisAlignment.center
                  ? Alignment.center
                  : Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: ResponsiveUtils.fontSize(context, valueFontSize ?? 14),
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

/// A scalable status badge widget
class ScalableStatusBadge extends StatelessWidget {
  final String status;
  final Color color;
  final IconData? icon;
  final double? fontSize;

  const ScalableStatusBadge({
    super.key,
    required this.status,
    required this.color,
    this.icon,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.spacing(context, 10),
        vertical: ResponsiveUtils.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: ResponsiveUtils.borderRadius(context, 16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: ResponsiveUtils.iconSize(context, 12),
              color: color,
            ),
            SizedBox(width: ResponsiveUtils.spacing(context, 4)),
          ],
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, fontSize ?? 12),
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A scalable grid view that adjusts columns based on screen size
class ScalableGridView extends StatelessWidget {
  final List<Widget> children;
  final double childAspectRatio;
  final double spacing;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  const ScalableGridView({
    super.key,
    required this.children,
    this.childAspectRatio = 1.0,
    this.spacing = 12,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveUtils.gridColumns(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: ResponsiveUtils.spacing(context, spacing),
        mainAxisSpacing: ResponsiveUtils.spacing(context, spacing),
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// A scalable horizontal list container
class ScalableHorizontalList extends StatelessWidget {
  final List<Widget> children;
  final double height;
  final double spacing;
  final EdgeInsets? padding;

  const ScalableHorizontalList({
    super.key,
    required this.children,
    required this.height,
    this.spacing = 12,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ResponsiveUtils.cardHeight(context, height),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(
          width: ResponsiveUtils.spacing(context, spacing),
        ),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

/// A scalable container with auto-sizing constraints
class ScalableContainer extends StatelessWidget {
  final Widget child;
  final double? minHeight;
  final double? maxHeight;
  final double? minWidth;
  final double? maxWidth;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BoxDecoration? decoration;

  const ScalableContainer({
    super.key,
    required this.child,
    this.minHeight,
    this.maxHeight,
    this.minWidth,
    this.maxWidth,
    this.padding,
    this.margin,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: minHeight != null
            ? ResponsiveUtils.h(context, minHeight!)
            : 0,
        maxHeight: maxHeight != null
            ? ResponsiveUtils.h(context, maxHeight!)
            : double.infinity,
        minWidth: minWidth != null
            ? ResponsiveUtils.w(context, minWidth!)
            : 0,
        maxWidth: maxWidth != null
            ? ResponsiveUtils.w(context, maxWidth!)
            : double.infinity,
      ),
      padding: padding,
      margin: margin,
      decoration: decoration,
      child: child,
    );
  }
}

/// A scalable button with proper padding and font sizing
class ScalableButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isOutlined;
  final bool isLoading;
  final double? fontSize;

  const ScalableButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.isOutlined = false,
    this.isLoading = false,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final buttonContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: ResponsiveUtils.iconSize(context, 18),
            height: ResponsiveUtils.iconSize(context, 18),
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        else if (icon != null)
          Icon(icon, size: ResponsiveUtils.iconSize(context, 18)),
        if (icon != null || isLoading)
          SizedBox(width: ResponsiveUtils.spacing(context, 8)),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, fontSize ?? 14),
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );

    if (isOutlined) {
      return OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor ?? AppColors.primary,
          padding: ResponsiveUtils.padding(context, horizontal: 16, vertical: 12),
          side: BorderSide(
            color: foregroundColor ?? AppColors.primary,
            width: 1.5,
          ),
        ),
        child: buttonContent,
      );
    }

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: foregroundColor ?? Colors.white,
        padding: ResponsiveUtils.padding(context, horizontal: 16, vertical: 12),
      ),
      child: buttonContent,
    );
  }
}

/// A scalable list tile for consistent list items
class ScalableListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets? contentPadding;

  const ScalableListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          fontSize: ResponsiveUtils.fontSize(context, 15),
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 13),
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: contentPadding ?? ResponsiveUtils.padding(context, horizontal: 16, vertical: 4),
    );
  }
}

/// A scalable empty state widget
class ScalableEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const ScalableEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: ResponsiveUtils.paddingAll(context, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: ResponsiveUtils.iconSize(context, 64),
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            SizedBox(height: ResponsiveUtils.spacing(context, 16)),
            Text(
              title,
              style: TextStyle(
                fontSize: ResponsiveUtils.fontSize(context, 18),
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: ResponsiveUtils.spacing(context, 8)),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: ResponsiveUtils.fontSize(context, 14),
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: ResponsiveUtils.spacing(context, 24)),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
