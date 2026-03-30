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
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            if (android.namespace == null) {
                android.namespace = "com.example.safevoice.${project.name.replace("-", "_")}"
            }
            // Vosk kütüphanesinin SDK versiyonlarýný senin telefonuna uygun hale getirelim
            if (project.name == "vosk_flutter") {
                android.compileSdkVersion(34)
                android.defaultConfig.minSdkVersion(24)
                android.defaultConfig.targetSdkVersion(34)
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
