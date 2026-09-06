allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureAndroid: (Project) -> Unit = { p ->
        val android = p.extensions.findByName("android")
        if (android != null) {
            try {
                val setCompileSdk = android.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterTypes.size == 1
                }
                if (setCompileSdk != null) {
                    setCompileSdk.invoke(android, 36)
                } else {
                    val compileSdkVersion = android.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" && it.parameterTypes.size == 1
                    }
                    compileSdkVersion?.invoke(android, 36)
                }
            } catch (_: Throwable) {}
        }
    }

    if (project.state.executed) {
        configureAndroid(project)
    } else {
        project.afterEvaluate {
            configureAndroid(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
