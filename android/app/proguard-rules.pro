# Play Core split-install is referenced from
# io.flutter.app.FlutterPlayStoreSplitApplication but we don't use it.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Flutter plugins frequently rely on reflection and JNI lookups, both of
# which break under R8's default aggressive shrinking. Keep the entry
# points that Flutter / Dart / our plugins call via reflection.

# Flutter embedding
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# kotlinx-serialization / kotlin stdlib reflection paths used by some
# transitive deps.
-keep class kotlin.Metadata { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlinx.**

# Coroutines uses ServiceLoader entries that R8 would otherwise strip.
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-dontwarn kotlinx.coroutines.**

# androidx.* APIs we touch through reflection (NotificationCompat,
# androidx.core).
-keep class androidx.core.app.** { *; }
-dontwarn androidx.**

# Our own classes — keep MainActivity / TransferNotifier /
# TransferForegroundService so the manifest references resolve after
# minification.
-keep class com.lanlink.app.MainActivity { *; }
-keep class com.lanlink.app.TransferNotifier { *; }
-keep class com.lanlink.app.TransferForegroundService { *; }

# permission_handler reflects on enum constants.
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# mobile_scanner / Google MLKit are not used at runtime in release builds
# unless the QR scanner screen is opened, but R8 has trouble with their
# DEX entry points — keep their public surface.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
