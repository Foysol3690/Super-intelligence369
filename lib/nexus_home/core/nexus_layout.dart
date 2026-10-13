import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show EdgeInsets;

/// Resolves every element's position from the available size and safe area.
/// All values are relative so the composition holds on 16:9 through 21:9 and
/// on narrow Android phones.
class NexusLayout {
  factory NexusLayout.resolve(Size size, EdgeInsets padding) {
    final w = size.width;
    final h = size.height;
    final scale = (w / 390).clamp(0.78, 1.3);

    final statusTop = padding.top + math.max(h * 0.022, 10);
    final statusHeight = (56 * scale).clamp(46.0, 70.0);
    final statusWidth = math.min(w * 0.86, 520.0);
    final statusRect = Rect.fromLTWH(
      (w - statusWidth) / 2,
      statusTop,
      statusWidth,
      statusHeight,
    );

    final micRadius = (w * 0.112).clamp(30.0, 52.0);
    final bottomInset = math.max(padding.bottom, 14.0);
    final micCenter = Offset(w / 2, h - bottomInset - micRadius - h * 0.05);

    final waveAmplitude = math.min(micRadius * 1.55, h * 0.07);
    final waveRect = Rect.fromLTRB(
      w * 0.015,
      micCenter.dy - waveAmplitude,
      w * 0.985,
      micCenter.dy + waveAmplitude,
    );

    final captionHeight = 64 * scale;
    final captionBottom =
        micCenter.dy - micRadius - math.max(h * 0.055, waveAmplitude * 0.9);
    final captionTop = captionBottom - captionHeight;

    final regionTop = statusRect.bottom + h * 0.02;
    final regionBottom = captionTop - h * 0.025;
    final regionHeight = math.max(regionBottom - regionTop, 120.0);
    final orbCenter = Offset(w / 2, regionTop + regionHeight * 0.48);
    final fieldRadius = math.min(w * 0.4, regionHeight * 0.42);

    return NexusLayout._(
      size: size,
      padding: padding,
      scale: scale.toDouble(),
      statusRect: statusRect,
      orbCenter: orbCenter,
      fieldRadius: fieldRadius,
      coreRadius: fieldRadius * 0.16,
      lensRadius: fieldRadius * 1.04,
      micCenter: micCenter,
      micRadius: micRadius,
      waveRect: waveRect,
      captionTop: captionTop,
      captionHeight: captionHeight,
    );
  }

  const NexusLayout._({
    required this.size,
    required this.padding,
    required this.scale,
    required this.statusRect,
    required this.orbCenter,
    required this.fieldRadius,
    required this.coreRadius,
    required this.lensRadius,
    required this.micCenter,
    required this.micRadius,
    required this.waveRect,
    required this.captionTop,
    required this.captionHeight,
  });

  final Size size;
  final EdgeInsets padding;
  final double scale;
  final Rect statusRect;
  final Offset orbCenter;

  /// Radius of the orbital ribbon structure.
  final double fieldRadius;

  /// Radius of the plasma sphere at the heart of the orb.
  final double coreRadius;

  /// Radius of the optical glass lens the orb is suspended in.
  final double lensRadius;
  final Offset micCenter;
  final double micRadius;
  final Rect waveRect;
  final double captionTop;
  final double captionHeight;

  Rect get captionRect =>
      Rect.fromLTWH(0, captionTop, size.width, captionHeight);

  /// Where the mic -> orb energy stream leaves the microphone.
  Offset get streamStart => micCenter.translate(0, -micRadius * 1.05);

  /// Where the energy stream enters the plasma core.
  Offset get streamEnd => orbCenter.translate(0, coreRadius * 1.1);

  @override
  bool operator ==(Object other) =>
      other is NexusLayout && other.size == size && other.padding == padding;

  @override
  int get hashCode => Object.hash(size, padding);
}
