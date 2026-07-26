# Flutter embedding / plugins
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# JNI / native callbacks used by plugins
-keepclasseswithmembernames class * {
    native <methods>;
}

# TensorFlow Lite (tflite_flutter)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Firebase / Play services (common noisy warnings)
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-dontwarn okhttp3.**
-dontwarn javax.annotation.**

# Kotlin
-dontwarn kotlin.**

# Play Core (referenced by Flutter embedding when deferred components not used)
-dontwarn com.google.android.play.core.**
