plugins {
    // ✅ 对齐 Flutter 官方组合（AGP 8.7.2 + Kotlin 2.0.21），避免 BaseVariant 等兼容性问题
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("dev.flutter.flutter-gradle-plugin") apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
