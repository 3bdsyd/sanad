allprojects {
    repositories {
        google()
        // Opt-in official Google CDN for networks returning 404 from dl.google.com.
        if (providers.gradleProperty("snadGoogleDownloadFallback").orNull == "true") {
            maven {
                name = "SanadGoogleDownloadFallback"
                url = uri("https://redirector.gvt1.com/edgedl/android/maven2/")
                content {
                    includeGroupByRegex("com\\.google\\..*")
                    includeGroupByRegex("androidx\\..*")
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
