plugins {
    // ✅ 对齐 Flutter 官方组合，避免 BaseVariant 等兼容性问题
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
