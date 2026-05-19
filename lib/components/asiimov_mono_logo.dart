import 'package:asiimov/constants/app_assets.dart';
import 'package:flutter/material.dart';

/// Monochrome logo tinted with [ColorScheme.onSurface] so it stays readable
/// in both light and dark themes.
class AsiimovMonoLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;

  const AsiimovMonoLogo({
    super.key,
    this.width = 100,
    this.height = 100,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.logoMono,
      width: width,
      height: height,
      fit: fit,
      color: Theme.of(context).colorScheme.onSurface,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
