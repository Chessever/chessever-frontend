allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Gradle 9 removed RepositoryHandler.jcenter(). stockfish 1.8.1, the newest
// release, still calls it in its android/build.gradle, and that one call fails
// configuration for the whole build ("Could not find method jcenter()").
// A closure stored as an extra property answers a method call of the same name
// in that project's script, so this turns the call into a no-op. JCenter has
// only redirected to Maven Central since 2024, so Maven Central is added to the
// plugin's buildscript repositories in its place. Delete this block once
// stockfish ships a build.gradle without jcenter().
subprojects {
    if (name == "stockfish") {
        extra["jcenter"] = KotlinClosure0<Any>({ Unit })
        buildscript.repositories.mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Force every Android + Kotlin subproject (app and all plugins) onto the same
// JVM target. Plugins like receive_sharing_intent, app_settings, etc. either
// don't pin or pin inconsistent targets (Java 1.8 / Kotlin 19, or Java 11 /
// Kotlin 17). Kotlin 2.1 strict validation then fails the build. Hook after
// each subproject evaluates so we run *after* the plugin's android {} DSL has
// set its values but *before* tasks are created — and place this block before
// evaluationDependsOn below, so projects are not yet evaluated when we attach
// the callback.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17

            if (project.name == "flutter_soloud") {
                androidExt.defaultConfig.externalNativeBuild {
                    cmake {
                        cppFlags("-DMA_NO_AAUDIO")
                    }
                }
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
