#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Select Java 17 for Android Gradle Plugin 8.5.2.
export JAVA_HOME="${JAVA_HOME:-$PREFIX/lib/jvm/java-17-openjdk}"

# Build the debug APK with the pinned Gradle wrapper.
./gradlew assembleDebug

# Print the resulting APK path.
printf '%s\n' "$PWD/app/build/outputs/apk/debug/app-debug.apk"
