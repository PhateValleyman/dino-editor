#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Select Java 17 for Android Gradle Plugin 8.6.1.
export JAVA_HOME="${JAVA_HOME:-$PREFIX/lib/jvm/java-17-openjdk}"

# Build the debug APK.
gradle assembleDebug

# Print the resulting APK path.
printf '%s\n' "$PWD/app/build/outputs/apk/debug/app-debug.apk"
