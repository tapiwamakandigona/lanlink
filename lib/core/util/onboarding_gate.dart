/// Pure decision helper for whether the welcome carousel should be shown.
///
/// Returns true when the user has never been onboarded (first run) or when
/// the app has been updated to a version they haven't seen the tour for yet.
/// Kept free of Flutter imports so it can be unit-tested in isolation.
bool shouldShowOnboarding({
  required String lastOnboardedVersion,
  required String currentVersion,
}) {
  final seen = lastOnboardedVersion.trim();
  if (seen.isEmpty) return true; // never onboarded
  return seen != currentVersion.trim(); // onboarded on an older build
}
