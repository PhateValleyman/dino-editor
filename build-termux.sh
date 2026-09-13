#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Select a working Termux JDK for Android Gradle Plugin 8.5.2.
if [ -n "${JAVA_HOME:-}" ]; then
	if ! "$JAVA_HOME/bin/java" -version >/dev/null 2>&1; then
		printf 'JAVA_HOME není funkční: %s\n' "$JAVA_HOME" >&2
		exit 1
	fi
elif [ -x "$PREFIX/lib/jvm/java-17-openjdk/bin/java" ] &&
		"$PREFIX/lib/jvm/java-17-openjdk/bin/java" -version >/dev/null 2>&1; then
	export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"
elif [ -x "$PREFIX/lib/jvm/java-21-openjdk/bin/java" ] &&
		"$PREFIX/lib/jvm/java-21-openjdk/bin/java" -version >/dev/null 2>&1; then
	export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
else
	printf '%s\n' 'Funkční Termux JDK nebylo nalezeno. Spusť: pkg reinstall openjdk-17' >&2
	exit 1
fi

# Build the debug APK with the pinned Gradle wrapper.
./gradlew assembleDebug

# Print the resulting APK path.
printf '%s\n' "$PWD/app/build/outputs/apk/debug/app-debug.apk"
