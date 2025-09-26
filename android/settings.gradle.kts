pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    plugins {
        id("com.android.application") version "8.5.2"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("dev.flutter.flutter-gradle-plugin") version "1.0.0"
    }

    resolutionStrategy {
        eachPlugin {
            when (requested.id.id) {
                "org.jetbrains.kotlin.android",
                "org.jetbrains.kotlin.jvm",
                "org.jetbrains.kotlin.multiplatform" -> useVersion("2.0.21")
            }
        }
    }

    // 读取 android/local.properties 中的 flutter.sdk
    val localProperties = java.util.Properties()
    val localPropertiesFile = java.io.File(settingsDir, "local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { localProperties.load(it) }
    }
    val flutterSdk: String = localProperties.getProperty("flutter.sdk")
        ?: throw GradleException("未在 android/local.properties 中找到 flutter.sdk，请填入你的 Flutter SDK 路径。")

    // 引入 Flutter 的 Gradle 插件
    includeBuild("$flutterSdk/packages/flutter_tools/gradle")
}

// Flutter 插件加载器（固定 1.0.0）
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "yicksync"
include(":app")
