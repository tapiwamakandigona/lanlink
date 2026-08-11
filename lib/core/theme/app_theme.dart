import 'package:flutter/material.dart';

/// The single LanLink brand colour. Every generated palette starts from this.
const _seed = Color(0xFF3D7BFF);

/// Hand-tuned surface + container overrides that sit on top of the
/// Material 3 generated scheme so the dark mode feels intentional rather
/// than "inverted Material defaults".
abstract final class AppTheme {
  // ─── Light ─────────────────────────────────────────────────────────
  static ThemeData light() {
    final base = ColorScheme.fromSeed(seedColor: _seed);
    return _build(base.copyWith(
      surface: const Color(0xFFF8F9FC),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF2F4F8),
      surfaceContainer: const Color(0xFFECEFF4),
      surfaceContainerHigh: const Color(0xFFE4E7EE),
      surfaceContainerHighest: const Color(0xFFDDE0E8),
    ));
  }

  // ─── Dark ──────────────────────────────────────────────────────────
  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return _build(base.copyWith(
      surface: const Color(0xFF0E1218),
      surfaceContainerLowest: const Color(0xFF080B0F),
      surfaceContainerLow: const Color(0xFF12171E),
      surfaceContainer: const Color(0xFF171C24),
      surfaceContainerHigh: const Color(0xFF1D232C),
      surfaceContainerHighest: const Color(0xFF232A34),
      onSurface: const Color(0xFFE2E4EA),
      onSurfaceVariant: const Color(0xFF9DA3B0),
      primary: const Color(0xFF8AB4FF),
      onPrimary: const Color(0xFF002E6A),
      primaryContainer: const Color(0xFF1B3A6B),
      onPrimaryContainer: const Color(0xFFD4E4FF),
      outline: const Color(0xFF3A4150),
      outlineVariant: const Color(0xFF2A303A),
    ));
  }

  // ─── Shared builder ────────────────────────────────────────────────
  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.25);
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
    );
  }

  /// Map the persisted string to a Flutter [ThemeMode].
  static ThemeMode resolve(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
