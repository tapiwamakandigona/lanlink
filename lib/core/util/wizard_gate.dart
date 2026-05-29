/// Pure decision helper for whether the launch-time pairing wizard
/// should be shown. Keeps the logic away from Flutter so we can unit-
/// test the three modes (`auto`, `always`, `never`) cleanly.
bool shouldShowPairingWizard({
  required String wizardMode,
  required bool hasLastPairing,
}) {
  switch (wizardMode) {
    case 'never':
      return false;
    case 'always':
      return true;
    case 'auto':
    default:
      // Auto mode: keep nudging the wizard until the user has paired
      // at least once. After that, the "Same as last time" shortcut
      // lives inside the home screen / settings; the wizard stops
      // hijacking every launch.
      return !hasLastPairing;
  }
}
