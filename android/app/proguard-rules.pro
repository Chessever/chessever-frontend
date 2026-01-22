##########################################
# ✅ Flutter & Plugin Keep Rules
##########################################
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

##########################################
# ✅ Firebase & Google Play Services
##########################################
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

##########################################
# ✅ Gson / JSON Serialization
##########################################
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

##########################################
# ✅ Retrofit / OkHttp / Supabase
##########################################
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-keep class io.supabase.** { *; }
-keep class kotlinx.coroutines.** { *; }

##########################################
# ✅ General Reflection / Serializable Models
##########################################
-keep class * implements java.io.Serializable { *; }

##########################################
# ✅ Suppress Common Warnings
##########################################
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
-dontwarn kotlin.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn com.google.android.gms.common.annotation.NoNullnessRewrite

##########################################
# ✅ Rules from missing_rules.txt
##########################################
# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn org.conscrypt.Conscrypt$Version
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.ConscryptHostnameVerifier
-dontwarn org.openjsse.javax.net.ssl.SSLParameters
-dontwarn org.openjsse.javax.net.ssl.SSLSocket
-dontwarn org.openjsse.net.ssl.OpenJSSE
##########################################
# ✅ Fix Missing Play Core Classes
##########################################
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
