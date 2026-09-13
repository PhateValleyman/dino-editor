#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Select JDK 17, which is the supported runtime for this Android Gradle Plugin version.
if [ -n "${JAVA_HOME:-}" ]; then
	if [ ! -x "$JAVA_HOME/bin/java" ]; then
		printf 'JAVA_HOME není funkční: %s\n' "$JAVA_HOME" >&2
		exit 1
	fi
	JAVA_VERSION=$("$JAVA_HOME/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)
	if [ "$JAVA_VERSION" != "17" ]; then
		printf 'Tento projekt vyžaduje JDK 17, ale JAVA_HOME ukazuje na JDK %s.\n' "${JAVA_VERSION:-neznámé}" >&2
		exit 1
	fi
else
	if [ ! -x "$PREFIX/lib/jvm/java-17-openjdk/bin/java" ]; then
		printf '%s\n' 'JDK 17 nebylo nalezeno. Spusť: pkg reinstall openjdk-17' >&2
		exit 1
	fi
	export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"
fi

# Export the selected JDK bin directory so Gradle and Java tools use the same runtime.
export PATH="$JAVA_HOME/bin:$PATH"

# Print the selected Java version before starting the build.
java -version

# Build the debug APK with the pinned Gradle wrapper.
./gradlew assembleDebug

# Print the resulting APK path.
printf '%s\n' "$PWD/app/build/outputs/apk/debug/app-debug.apk"
