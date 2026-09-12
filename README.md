# Dino Park Editor 1.2

Root Android editor for the `pl.idreams.Dino` PlayerPrefs save.

## What was fixed/improved

- Split the original concatenated source dump into a valid Gradle project.
- Modernized the Gradle configuration to AGP 8.6.1.
- Kept the app dependency-free at runtime.
- Kept Java 8 bytecode compatibility.
- Added dark/system theme resources.
- Hardened root command execution by draining stdout/stderr concurrently.
- Added input path validation.
- Added a save snapshot so UI edits cannot race the background save operation.
- Backup creation is now checked instead of silently ignored.
- Launching the game is now checked for failure.
- Kept the original save encoding/decoding format and editor semantics.

## Build in Termux

Use JDK 17 for the Gradle build. AGP 8.6.1 is intended for Gradle 8.7.

```bash
# Select Java 17 for Android/Gradle tooling.
export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"

# Verify the Java runtime used by Gradle.
java -version

# Build the debug APK.
gradle --offline assembleDebug
```

If the required Android Gradle Plugin is not cached, remove `--offline` on the first build.

The APK is created at:

`app/build/outputs/apk/debug/app-debug.apk`

## Root requirements

The editor uses `su` and therefore requires a rooted Android device with Magisk/root access.

The default save path is:

`/data/user/0/pl.idreams.Dino/shared_prefs/pl.idreams.Dino.v2.playerprefs.xml`

The loader also automatically falls back to `/data/data/...` and scans both locations for an XML PlayerPrefs file containing the `<string name="save">` field. This makes the editor work across Android versions where `/data/data` is only a compatibility path.

The game is force-stopped before reading/writing the save.

## Important

Make a backup before editing a new save. The editor also creates a timestamped `.bak.YYYYMMDD_HHMMSS` backup before saving.
