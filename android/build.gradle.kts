import com.android.build.gradle.BaseExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

    // tflite_flutter ships Java 11; Kotlin must match (plugin defaults to 21 on newer toolchains).
    afterEvaluate {
        val use11 = project.name == "tflite_flutter"
        val javaVersion = if (use11) JavaVersion.VERSION_11 else JavaVersion.VERSION_17
        val kotlinTarget = if (use11) JvmTarget.JVM_11 else JvmTarget.JVM_17

        extensions.findByType(BaseExtension::class.java)?.compileOptions?.apply {
            sourceCompatibility = javaVersion
            targetCompatibility = javaVersion
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(kotlinTarget)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
