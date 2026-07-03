import 'package:flutter/material.dart';

/// Design tokens for the LanLink v4 "Ember on Paper" system.
///
/// Everything visual in `lib/ui/v4/` flows from these tokens plus the
/// [ColorScheme] built in `ember_theme.dart`. Components must never
/// hard-code a `Color(0x...)` — semantic colors come from [EmberSemantics]
/// (a ThemeExtension), brand/neutral colors from `Theme.of(context).colorScheme`.

// ─── Spacing ──────────────────────────────────────────────────────────
/// 4px-based spacing scale. All padding/gaps in v4 use these values.
abstract final class VSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
}

// ─── Radii ────────────────────────────────────────────────────────────
/// Corner radius voice: "warm product". Small controls 10, cards 16,
/// sheets/hero surfaces 24, pills full.
abstract final class VRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(lg));
}

// ─── Type scale ───────────────────────────────────────────────────────
/// Fixed type scale: 12 / 13 / 15 / 17 / 22 / 28 / 40.
/// Weights: w400 body, w600 emphasis, w700 display.
abstract final class VType {
  static const TextStyle display = TextStyle(
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
  );
  static const TextStyle title = TextStyle(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static const TextStyle heading = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Tabular figures for live numbers (speed, ETA, progress %) so they
  /// don't jitter while updating.
  static const TextStyle numeric = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

// ─── Motion ───────────────────────────────────────────────────────────
/// Standard durations/curves so component transitions feel uniform.
abstract final class VMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Curve ease = Curves.easeOutCubic;
}

// ─── QR plate ─────────────────────────────────────────────────────────
/// The QR code is always dark ink on a light plate — in BOTH themes — so
/// any camera can read it. These are functional scan colors, not styling;
/// they live here so components stay literal-free.
abstract final class VQr {
  static const Color plate = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF241C16);
}

// ─── Semantic colors ──────────────────────────────────────────────────
/// The ONE place semantic status colors exist in v4.
///
/// `success` is the single green in the entire system — the v3 bug of three
/// competing success greens is structurally impossible: components read
/// `context.ember.success`, never a literal.
@immutable
class EmberSemantics extends ThemeExtension<EmberSemantics> {
  const EmberSemantics({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  /// The single semantic green. Nothing else in v4 may be green.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  static const light = EmberSemantics(
    // Success — moss green, warm enough to sit on paper.
    success: Color(0xFF2E6B3F),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD9EBDC),
    onSuccessContainer: Color(0xFF174023),
    // Warning — amber, clearly distinct from the copper brand.
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF6E3B8),
    onWarningContainer: Color(0xFF4A3000),
    // Danger — brick red.
    danger: Color(0xFFA83224),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFF6DAD4),
    onDangerContainer: Color(0xFF5C160E),
  );

  static const dark = EmberSemantics(
    success: Color(0xFF8FCC9C),
    onSuccess: Color(0xFF0E2E18),
    successContainer: Color(0xFF23472E),
    onSuccessContainer: Color(0xFFC6E8CD),
    warning: Color(0xFFE8BE6A),
    onWarning: Color(0xFF3C2700),
    warningContainer: Color(0xFF5C4300),
    onWarningContainer: Color(0xFFF8E3B9),
    danger: Color(0xFFF0A196),
    onDanger: Color(0xFF44100A),
    dangerContainer: Color(0xFF6E2118),
    onDangerContainer: Color(0xFFFAD7D0),
  );

  @override
  EmberSemantics copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
  }) {
    return EmberSemantics(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
    );
  }

  @override
  EmberSemantics lerp(EmberSemantics? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EmberSemantics(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      onDangerContainer: l(onDangerContainer, other.onDangerContainer),
    );
  }
}

/// Convenience accessor: `context.ember.success`.
extension EmberSemanticsX on BuildContext {
  EmberSemantics get ember =>
      Theme.of(this).extension<EmberSemantics>() ?? EmberSemantics.light;
}
