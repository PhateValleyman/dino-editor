# Dino Park Editor 1.2

Root Android editor for the `pl.idreams.Dino` PlayerPrefs save.

## What was fixed/improved

- Split the original concatenated source dump into a valid Gradle project.
- Uses Android Gradle Plugin 8.5.2 with Gradle 8.7.
- Kept the app dependency-free at runtime.
- Kept Java 8 bytecode compatibility.
- Added dark/system theme resources.
- Hardened root command execution by draining stdout/stderr concurrently.
- Added input path validation.
- Finds the save through `dumpsys package` and the app's actual `dataDir`, not only through a fixed filename.
- Added a save snapshot so UI edits cannot race the background save operation.
- Backup creation is now checked instead of silently ignored.
- Launching the game is now checked for failure.
- Kept the original save encoding/decoding format and editor semantics.

## Build in Termux

Use JDK 17 for the Gradle build. The project uses Android Gradle Plugin 8.5.2 with Gradle 8.7.

Pokud `java -version` skončí chybou `UnsatisfiedLinkError` nebo `initInetAddressIDs`,
je instalace JDK v Termuxu poškozená či smíchaná z různých verzí. Oprav ji před
buildem:

```bash
pkg update
pkg reinstall openjdk-17
```

Skript nejdříve ověří `JAVA_HOME`, potom automaticky zkusí JDK 17 a JDK 21.

```bash
# Select Java 17 for Android/Gradle tooling.
export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"

# Verify the Java runtime used by Gradle.
java -version

# Build the debug APK.
./gradlew --offline assembleDebug
```

If the required Android Gradle Plugin is not cached, remove `--offline` on the first build.

The APK is created at:

`app/build/outputs/apk/debug/app-debug.apk`

## Root requirements

The editor uses `su` and therefore requires a rooted Android device with Magisk/root access.

The default save path is `/data/data/pl.idreams.Dino/shared_prefs/pl.idreams.Dino.v2.playerprefs.xml`.
The loader first runs `dumpsys package pl.idreams.Dino` as root, obtains the actual
`dataDir`, and searches its `shared_prefs` directory for any XML containing
`<string name="save">`. It then falls back to `/data/user/0/...` and `/data/data/...`.
No `aapt2` binary is required or bundled; `dumpsys` is part of Android.

The game is force-stopped before reading/writing the save.

## Important

Make a backup before editing a new save. The editor also creates a timestamped `.bak.YYYYMMDD_HHMMSS` backup before saving.
