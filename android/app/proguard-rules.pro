# TFLite
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.** { *; }

# media_kit
-keep class com.alexmercerind.** { *; }
-keep class com.mediakit.** { *; }

# FFmpeg Kit
-keep class com.arthenica.** { *; }

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
