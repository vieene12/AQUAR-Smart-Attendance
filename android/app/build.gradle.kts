plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smart_attendance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.smart_attendance"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
            manifestPlaceholders["appLabel"] = "Smart Attendance"
        }
        create("emutest") {
            dimension = "environment"
            applicationIdSuffix = ".emutest"
            versionNameSuffix = "-emutest"
            manifestPlaceholders["appLabel"] = "Smart Attendance Emulator"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    beforeVariants(selector().withFlavor("environment" to "emutest")) {
        if (it.buildType != "debug") {
            it.enable = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core:1.17.0")
}

// The emutest app initializes the Firebase demo project explicitly from Dart.
// Never process the production google-services.json for this isolated variant.
tasks.configureEach {
    if (name.startsWith("processEmutest") && name.endsWith("GoogleServices")) {
        enabled = false
    }
    if (name.startsWith("compileFlutterBuildEmutest")) {
        doFirst {
            val target = project.findProperty("target")
                ?.toString()
                ?.replace('\\', '/')
            require(target?.endsWith("lib/main_emutest.dart") == true) {
                "The emutest flavor must use -t lib/main_emutest.dart."
            }
        }
    }
}
