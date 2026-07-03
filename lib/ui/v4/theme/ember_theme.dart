import 'package:flutter/material.dart';

import 'tokens.dart';

/// LanLink v4 "Ember on Paper" theme.
///
/// Warm copper/ember brand color on paper-like neutral surfaces. Elevation
/// language is hairline borders on tinted paper, not shadows. Confident,
/// warm, appliance-like.
///
/// All v4 components read colors exclusively from the [ColorScheme] and the
/// [EmberSemantics] extension registered here.
abstract final class EmberTheme {
  /// The single brand seed: copper ember.
  static const Color seed = Color(0xFFB4511E);

  // ─── Light: warm paper ──────────────────────────────────────────────
  static ThemeData light() {
    final base = ColorScheme.fromSeed(seedColor: seed);
    final scheme = base.copyWith(
      primary: const Color(0xFFA0430F),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFFFDBC9),
      onPrimaryContainer: const Color(0xFF55200A),
      secondary: const Color(0xFF755848),
      secondaryContainer: const Color(0xFFF4DED2),
      onSecondaryContainer: const Color(0xFF3F2A1D),
      // Paper: warm off-white, never pure white except the lowest card.
      surface: const Color(0xFFFAF5F0),
      onSurface: const Color(0xFF241C16),
      onSurfaceVariant: const Color(0xFF6C5F55),
      surfaceContainerLowest: const Color(0xFFFFFDFB),
      surfaceContainerLow: const Color(0xFFF4EDE6),
      surfaceContainer: const Color(0xFFEFE6DD),
      surfaceContainerHigh: const Color(0xFFE9DFD5),
      surfaceContainerHighest: const Color(0xFFE2D6CB),
      outline: const Color(0xFF897B70),
      outlineVariant: const Color(0xFFDACCC0),
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, EmberSemantics.light);
  }

  // ─── Dark: embers at night ──────────────────────────────────────────
  static ThemeData dark() {
    final base =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final scheme = base.copyWith(
      primary: const Color(0xFFFFB68F),
      onPrimary: const Color(0xFF54200A),
      primaryContainer: const Color(0xFF793413),
      onPrimaryContainer: const Color(0xFFFFDBC9),
      secondary: const Color(0xFFE3BFAB),
      secondaryContainer: const Color(0xFF5B4132),
      onSecondaryContainer: const Color(0xFFF4DED2),
      // Warm charcoal, faintly brown — not blue-black.
      surface: const Color(0xFF17120E),
      onSurface: const Color(0xFFEDE1D8),
      onSurfaceVariant: const Color(0xFFA69688),
      surfaceContainerLowest: const Color(0xFF100C09),
      surfaceContainerLow: const Color(0xFF1E1813),
      surfaceContainer: const Color(0xFF241D17),
      surfaceContainerHigh: const Color(0xFF2B231C),
      surfaceContainerHighest: const Color(0xFF332A22),
      outline: const Color(0xFF8A7A6D),
      outlineVariant: const Color(0xFF3E342B),
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, EmberSemantics.dark);
  }

  // ─── Shared builder ─────────────────────────────────────────────────
  static ThemeData _build(ColorScheme scheme, EmberSemantics semantics) {
    // Merge our type tokens over the platform defaults so the font family
    // (and any future custom face) is inherited, not clobbered.
    final baseText =
        ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;
    final buttonLabel =
        baseText.labelLarge!.merge(VType.label.copyWith(fontSize: 15));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [semantics],
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: baseText.titleLarge!
            .merge(VType.heading)
            .copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: VRadius.mdAll,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLow,
        labelStyle: baseText.labelLarge!
            .merge(VType.label)
            .copyWith(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: VRadius.smAll),
          padding: const EdgeInsets.symmetric(
              horizontal: VSpace.x5, vertical: VSpace.x3),
          textStyle: buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: VRadius.smAll),
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(
              horizontal: VSpace.x5, vertical: VSpace.x3),
          textStyle: buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: VRadius.smAll),
          foregroundColor: scheme.primary,
          textStyle: buttonLabel,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: VRadius.sheetTop),
        showDragHandle: true,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: VRadius.lgAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: VType.body.copyWith(color: scheme.onSurface),
        shape: const RoundedRectangleBorder(borderRadius: VRadius.smAll),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
    );
  }
}
