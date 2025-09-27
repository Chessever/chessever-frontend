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
        id("com.google.gms.google-services") version "4.3.15" apply false
    }

    android {
        namespace = "com.chessever.app"
        compileSdk = 36
        ndkVersion = "27.0.12077973"

        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_11
            targetCompatibility = JavaVersion.VERSION_11
            isCoreLibraryDesugaringEnabled = true
        }   

        kotlinOptions {
            jvmTarget = JavaVersion.VERSION_11.toString()
        }

        signingConfigs {
            if (keystorePropertiesFile.exists()) {
                create("release") {
                    keyAlias = keystoreProperties["keyAlias"]?.toString()
                    keyPassword = keystoreProperties["keyPassword"]?.toString()
                    storeFile = keystoreProperties["storeFile"]?.let { file(it.toString()) }
                    storePassword = keystoreProperties["storePassword"]?.toString()
                }
            }
        }

        buildTypes {
            getByName("release") {
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
        }

        defaultConfig {
            // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
            applicationId = "com.chessever.app"
            // You can update the following values to match your application needs.
            // For more information, see: https://flutter.dev/to/review-gradle-config.
            minSdk = flutter.minSdkVersion
            targetSdk = 36
            versionCode = 36
            versionName = "2.0.35"
        }

    }
    dependencies {
        // Latest stable Kotlin version compatible with Flutter 2025
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.0.21")

        // Core library desugaring dependency
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    }


    flutter {
        source = "../.."
    }
