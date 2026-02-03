import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A comprehensive responsive utility class for handling screen sizes,
/// scaling, and preventing overflow issues across the entire app.
class ResponsiveUtils {
  ResponsiveUtils._();

  // Base design dimensions (based on standard mobile design)
  static const double _baseWidth = 375.0;
  static const double _baseHeight = 812.0;

  // Breakpoints
  static const double mobileBreakpoint = 480;
  static const double tabletBreakpoint = 768;
  static const double desktopBreakpoint = 1024;

  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height;
  }

  /// Get safe area padding
  static EdgeInsets safePadding(BuildContext context) {
    return MediaQuery.paddingOf(context);
  }

  /// Get the scale factor for width-based scaling
  static double widthScale(BuildContext context) {
    return screenWidth(context) / _baseWidth;
  }

  /// Get the scale factor for height-based scaling
  static double heightScale(BuildContext context) {
    return screenHeight(context) / _baseHeight;
  }

  /// Get a balanced scale factor (average of width and height)
  static double scale(BuildContext context) {
    final widthFactor = widthScale(context);
    final heightFactor = heightScale(context);
    return (widthFactor + heightFactor) / 2;
  }

  /// Scale a width value responsively
  static double w(BuildContext context, double size) {
    return size * widthScale(context);
  }

  /// Scale a height value responsively
  static double h(BuildContext context, double size) {
    return size * heightScale(context);
  }

  /// Scale a value using the balanced scale factor
  static double s(BuildContext context, double size) {
    return size * scale(context);
  }

  /// Get responsive font size with min/max constraints
  static double fontSize(BuildContext context, double size) {
    final scaleFactor = widthScale(context);
    final textScaler = MediaQuery.textScalerOf(context);
    // Clamp the scale to prevent text from being too small or too large
    final clampedScale = scaleFactor.clamp(0.8, 1.3);
    // Also consider system text scale but with limits
    final clampedTextScale = textScaler.scale(1.0).clamp(0.85, 1.3);
    return size * clampedScale * clampedTextScale;
  }

  /// Get responsive font size that adapts but stays within readable bounds
  static double adaptiveFontSize(BuildContext context, double baseSize, {
    double minSize = 10,
    double maxSize = 32,
  }) {
    final calculated = fontSize(context, baseSize);
    return calculated.clamp(minSize, maxSize);
  }

  /// Get responsive padding
  static EdgeInsets padding(
    BuildContext context, {
    double horizontal = 16,
    double vertical = 16,
  }) {
    final scaleFactor = scale(context).clamp(0.8, 1.2);
    return EdgeInsets.symmetric(
      horizontal: horizontal * scaleFactor,
      vertical: vertical * scaleFactor,
    );
  }

  /// Get responsive margin
  static EdgeInsets margin(
    BuildContext context, {
    double horizontal = 0,
    double vertical = 0,
  }) {
    final scaleFactor = scale(context).clamp(0.8, 1.2);
    return EdgeInsets.symmetric(
      horizontal: horizontal * scaleFactor,
      vertical: vertical * scaleFactor,
    );
  }

  /// Get responsive all-sides padding
  static EdgeInsets paddingAll(BuildContext context, double value) {
    final scaleFactor = scale(context).clamp(0.8, 1.2);
    return EdgeInsets.all(value * scaleFactor);
  }

  /// Get responsive border radius
  static BorderRadius borderRadius(BuildContext context, double radius) {
    final scaleFactor = scale(context).clamp(0.8, 1.2);
    return BorderRadius.circular(radius * scaleFactor);
  }

  /// Get responsive icon size
  static double iconSize(BuildContext context, double size) {
    final scaleFactor = widthScale(context).clamp(0.85, 1.25);
    return size * scaleFactor;
  }

  /// Get responsive spacing (SizedBox height or width)
  static double spacing(BuildContext context, double size) {
    final scaleFactor = scale(context).clamp(0.8, 1.2);
    return size * scaleFactor;
  }

  /// Get responsive card height that prevents overflow
  static double cardHeight(BuildContext context, double baseHeight) {
    final scaleFactor = heightScale(context).clamp(0.85, 1.3);
    return baseHeight * scaleFactor;
  }

  /// Check if device is in portrait mode
  static bool isPortrait(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.portrait;
  }

  /// Check if device is in landscape mode
  static bool isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  /// Check if device is mobile
  static bool isMobile(BuildContext context) {
    return screenWidth(context) < tabletBreakpoint;
  }

  /// Check if device is tablet
  static bool isTablet(BuildContext context) {
    final width = screenWidth(context);
    return width >= tabletBreakpoint && width < desktopBreakpoint;
  }

  /// Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return screenWidth(context) >= desktopBreakpoint;
  }

  /// Get the number of columns for a grid based on screen size
  static int gridColumns(BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Get responsive value based on device type
  static T valueByDevice<T>(BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  /// Calculate available height considering safe areas
  static double availableHeight(BuildContext context) {
    final screenH = screenHeight(context);
    final padding = safePadding(context);
    return screenH - padding.top - padding.bottom;
  }

  /// Calculate available width considering safe areas
  static double availableWidth(BuildContext context) {
    final screenW = screenWidth(context);
    final padding = safePadding(context);
    return screenW - padding.left - padding.right;
  }

  /// Get keyboard height if visible
  static double keyboardHeight(BuildContext context) {
    return MediaQuery.viewInsetsOf(context).bottom;
  }

  /// Check if keyboard is visible
  static bool isKeyboardVisible(BuildContext context) {
    return keyboardHeight(context) > 0;
  }

  /// Get the maximum width for content (useful for tablets/desktops)
  static double contentMaxWidth(BuildContext context, {double maxWidth = 600}) {
    return math.min(screenWidth(context), maxWidth);
  }
}

/// Extension methods for easy access to responsive values
extension ResponsiveContext on BuildContext {
  /// Quick access to screen width
  double get screenWidth => ResponsiveUtils.screenWidth(this);

  /// Quick access to screen height
  double get screenHeight => ResponsiveUtils.screenHeight(this);

  /// Quick access to check if mobile
  bool get isMobile => ResponsiveUtils.isMobile(this);

  /// Quick access to check if tablet
  bool get isTablet => ResponsiveUtils.isTablet(this);

  /// Quick access to check if desktop
  bool get isDesktop => ResponsiveUtils.isDesktop(this);

  /// Quick access to check if portrait
  bool get isPortrait => ResponsiveUtils.isPortrait(this);

  /// Quick access to check if landscape
  bool get isLandscape => ResponsiveUtils.isLandscape(this);

  /// Quick access to responsive font size
  double rFontSize(double size) => ResponsiveUtils.fontSize(this, size);

  /// Quick access to responsive spacing
  double rSpacing(double size) => ResponsiveUtils.spacing(this, size);

  /// Quick access to responsive icon size
  double rIconSize(double size) => ResponsiveUtils.iconSize(this, size);

  /// Quick access to responsive padding
  EdgeInsets rPadding({double horizontal = 16, double vertical = 16}) =>
      ResponsiveUtils.padding(this, horizontal: horizontal, vertical: vertical);

  /// Quick access to responsive all-sides padding
  EdgeInsets rPaddingAll(double value) => ResponsiveUtils.paddingAll(this, value);

  /// Quick access to responsive border radius
  BorderRadius rBorderRadius(double radius) =>
      ResponsiveUtils.borderRadius(this, radius);

  /// Quick access to responsive value by device
  T byDevice<T>({required T mobile, T? tablet, T? desktop}) =>
      ResponsiveUtils.valueByDevice(this, mobile: mobile, tablet: tablet, desktop: desktop);
}

/// A responsive text widget that automatically scales
class ResponsiveText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;

  const ResponsiveText(
    this.text, {
    super.key,
    this.fontSize = 14,
    this.fontWeight,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final responsiveFontSize = ResponsiveUtils.fontSize(context, fontSize);
    
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: (style ?? const TextStyle()).copyWith(
        fontSize: responsiveFontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }
}

/// A responsive container that prevents overflow
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? minHeight;
  final double? maxHeight;
  final double? minWidth;
  final double? maxWidth;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BoxDecoration? decoration;

  const ResponsiveContainer({
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
        minHeight: minHeight ?? 0,
        maxHeight: maxHeight ?? double.infinity,
        minWidth: minWidth ?? 0,
        maxWidth: maxWidth ?? double.infinity,
      ),
      padding: padding,
      margin: margin,
      decoration: decoration,
      child: child,
    );
  }
}

/// A widget that wraps content and ensures it fits within available space
class FitContent extends StatelessWidget {
  final Widget child;
  final BoxFit fit;
  final Alignment alignment;

  const FitContent({
    super.key,
    required this.child,
    this.fit = BoxFit.scaleDown,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: fit,
      alignment: alignment,
      child: child,
    );
  }
}

/// A mixin that provides responsive utilities to StatefulWidgets
mixin ResponsiveMixin<T extends StatefulWidget> on State<T> {
  double get screenWidth => ResponsiveUtils.screenWidth(context);
  double get screenHeight => ResponsiveUtils.screenHeight(context);
  bool get isMobile => ResponsiveUtils.isMobile(context);
  bool get isTablet => ResponsiveUtils.isTablet(context);
  bool get isDesktop => ResponsiveUtils.isDesktop(context);
  bool get isPortrait => ResponsiveUtils.isPortrait(context);
  bool get isLandscape => ResponsiveUtils.isLandscape(context);

  double rFontSize(double size) => ResponsiveUtils.fontSize(context, size);
  double rSpacing(double size) => ResponsiveUtils.spacing(context, size);
  double rIconSize(double size) => ResponsiveUtils.iconSize(context, size);
  double rCardHeight(double size) => ResponsiveUtils.cardHeight(context, size);
  EdgeInsets rPadding({double horizontal = 16, double vertical = 16}) =>
      ResponsiveUtils.padding(context, horizontal: horizontal, vertical: vertical);
  EdgeInsets rPaddingAll(double value) => ResponsiveUtils.paddingAll(context, value);
  BorderRadius rBorderRadius(double radius) =>
      ResponsiveUtils.borderRadius(context, radius);
}

/// A responsive SizedBox helper
class RSizedBox extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget? child;

  const RSizedBox({
    super.key,
    this.width,
    this.height,
    this.child,
  });

  const RSizedBox.horizontal(this.width, {super.key})
      : height = null,
        child = null;

  const RSizedBox.vertical(this.height, {super.key})
      : width = null,
        child = null;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width != null ? ResponsiveUtils.spacing(context, width!) : null,
      height: height != null ? ResponsiveUtils.spacing(context, height!) : null,
      child: child,
    );
  }
}

/// A responsive card widget that adapts its size
class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final double? minHeight;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final double? elevation;
  final BorderRadius? borderRadius;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.minHeight,
    this.padding,
    this.margin,
    this.color,
    this.elevation,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      color: color,
      margin: margin ?? EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? ResponsiveUtils.borderRadius(context, 12),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight ?? 0,
        ),
        child: Padding(
          padding: padding ?? ResponsiveUtils.paddingAll(context, 12),
          child: child,
        ),
      ),
    );
  }
}

/// A utility class for creating adaptive layouts
class AdaptiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveUtils.isDesktop(context)) {
      return desktop ?? tablet ?? mobile;
    }
    if (ResponsiveUtils.isTablet(context)) {
      return tablet ?? mobile;
    }
    return mobile;
  }
}
