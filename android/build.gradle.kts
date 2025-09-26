buildscript {
    // Flutter 的 flutter.gradle 会优先读取 "kotlin.version" 或 "kotlin_version" 这两个 extra 属性
    // 若不手动对齐，Flutter 注入的旧版 Kotlin 插件会先进入 buildscript classpath，
    // 之后即便 plugins {} 请求 2.0.x 版本也会因为 "unknown version" 而无法覆盖，进而触发 BaseVariant 缺失。
    extra.apply {
        set("kotlin.version", "2.0.21")
        set("kotlin_version", "2.0.21")
    }
}

plugins {
    // ✅ 与 Kotlin 2.0.21 保持兼容的组合（AGP 8.5.2 + Kotlin 2.0.21），避免 BaseVariant 等兼容性问题
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("dev.flutter.flutter-gradle-plugin") apply false
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
