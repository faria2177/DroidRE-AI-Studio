plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Explicit release mode. A missing/invalid production signing setting fails
// the build rather than silently falling back to the debug identity.
val productionSigning = System.getenv("DROIDRE_PRODUCTION_SIGNING") == "1"
fun requiredSigningEnv(name: String): String =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Missing environment variable: $name")

android {
    if (productionSigning) {
        signingConfigs {
            create("ownerRelease") {
                val source = file(requiredSigningEnv("DROIDRE_KEYSTORE"))
                require(source.isFile) { "Owner keystore does not exist" }
                val alias = requiredSigningEnv("DROIDRE_KEY_ALIAS")
                require(!alias.equals("androiddebugkey", ignoreCase = true) &&
                    !source.name.equals("debug.keystore", ignoreCase = true)) {
                    "Debug keystore and alias are not allowed in production mode"
                }
                storeFile = source
                storePassword = requiredSigningEnv("DROIDRE_STORE_PASSWORD")
                keyAlias = alias
                keyPassword = requiredSigningEnv("DROIDRE_KEY_PASSWORD")
            }
        }
    }

    namespace = "com.jahid.droidreai"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.jahid.droidreai"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (productionSigning) "ownerRelease" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
