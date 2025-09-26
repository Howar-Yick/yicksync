// yicksync/android/build.gradle.kts (项目级)

plugins {
    id("com.android.application") version "8.4.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    id("dev.flutter.flutter-gradle-plugin") apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}