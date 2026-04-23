allprojects {
    repositories {
        google()
        mavenCentral()
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
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            kotlinOptions {
                jvmTarget = "17"
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
