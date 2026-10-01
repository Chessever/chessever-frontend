    import java.util.Properties

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")

    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }



    plugins {
        id("com.android.application")
        id("kotlin-android")
        id("dev.flutter.flutter-gradle-plugin")
        id("com.google.gms.google-services")
    }

    android {
        namespace = "com.chessEver.app"
        compileSdk = 36
        // ndkVersion = "27.0.12077973"
    ndkVersion = "28.2.13676358"

        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
            isCoreLibraryDesugaringEnabled = true
        }

        signingConfigs {
            if (keystorePropertiesFile.exists()) {
                create("release") {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                }
            }
        }



        defaultConfig {
            // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
            applicationId = "com.chessEver.app"
            // You can update the following values to match your application needs.
            // For more information, see: https://flutter.dev/to/review-gradle-config.
            minSdk = flutter.minSdkVersion
            targetSdk = 36
            versionCode = flutter.versionCode
            versionName = flutter.versionName
            testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
            testInstrumentationRunnerArguments["clearPackageData"] = "true"
            manifestPlaceholders["appName"] = "ChessEver"
            manifestPlaceholders["authRedirectScheme"] = "com.chessever.app"
        }

        // Dart defines keep the native SDK app id paired with the ad units.
        val adDefines = (project.findProperty("dart-defines") as? String)
            ?.split(",")?.mapNotNull { encoded ->
                val decoded = String(java.util.Base64.getDecoder().decode(encoded))
                val parts = decoded.split("=", limit = 2)
                if (parts.size == 2) parts[0] to parts[1] else null
            }?.toMap() ?: emptyMap()
        defaultConfig {
            manifestPlaceholders["admobAppId"] =
                "ca-app-pub-3940256099942544~3347511713"
        }

        flavorDimensions += "environment"
        productFlavors {
            create("production") {
                dimension = "environment"
                manifestPlaceholders["admobAppId"] = adDefines["ADMOB_ANDROID_APP_ID"]
                    ?: "ca-app-pub-3681310687796023~4858872090"
                manifestPlaceholders["appName"] = "ChessEver"
                manifestPlaceholders["authRedirectScheme"] = "com.chessever.app"
            }
            create("chessevertest") {
                dimension = "environment"
                applicationIdSuffix = ".test"
                manifestPlaceholders["appName"] = "ChessEver Test"
                manifestPlaceholders["authRedirectScheme"] = "com.chessever.app.test"
            }
        }

        testOptions {
            execution = "ANDROIDX_TEST_ORCHESTRATOR"
        }

        buildTypes {
            release {
                isMinifyEnabled = true
                isShrinkResources = true
                proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro"
                )
                if (keystorePropertiesFile.exists()) {
                    signingConfig = signingConfigs.getByName("release")
                }
            }
            debug {
                isMinifyEnabled = false
                isShrinkResources = false
            }
        }

    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    dependencies {
        // Latest stable Kotlin version compatible with Flutter 2025
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.2.20")

        // Ensure okhttp is present for Amplitude's Android core (R8 was missing HttpUrl)
        implementation("com.squareup.okhttp3:okhttp:4.12.0")

        // OneSignal Android SDK for notification service extension
        implementation("com.onesignal:OneSignal:[5.0.0, 6.0.0)")

        // Core library desugaring dependency
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

        androidTestUtil("androidx.test:orchestrator:1.5.1")

    }


    flutter {
        source = "../.."
    }
