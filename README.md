# Dino Editor 1.4

Root Android editor for the `pl.idreams.Dino` PlayerPrefs save.
The editor application ID is `cz.umbrellacorp.dinoeditor`.

## What is included

- Valid Gradle Android project using Android Gradle Plugin 8.5.2 and Gradle 8.7.
- No external runtime dependencies.
- Java 8 bytecode compatibility; build with JDK 17.
- Dark/system theme resources.
- Root command execution with concurrent stdout/stderr draining.
- Automatic save discovery through `dumpsys package` and the app's actual `dataDir`.
- Support for both `/data/user/0/...` and `/data/data/...` layouts and non-standard PlayerPrefs filenames.
- Dino list with level, cage, ID and UNICORN status.
- Currency/resources editing.
- Cage and building levels, arena statistics, unlock flags and bone completion.
- In-memory save snapshot before writing.
- Timestamped backup before every save.
- Atomic save write through a temporary file followed by `mv`, preventing a failed write from truncating the original save.
- Post-write read/decode verification before the game is launched.
- Protection against overlapping load/save operations.
- Input validation for numeric editor values.

## Build in Termux

Use JDK 17 for the Gradle build.

If `java -version` fails with `UnsatisfiedLinkError` or `initInetAddressIDs`, the Termux JDK installation is broken or mixed between versions. Repair it first:

```bash
# Refresh the Termux package indexes.
pkg update

# Reinstall the JDK 17 package used by the Android build.
pkg reinstall openjdk-17
```

Then build:

```bash
# Select Java 17 for Android/Gradle tooling.
export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"

# Verify the Java runtime used by Gradle.
java -version

# Build the debug APK.
./gradlew assembleDebug
```

If the Android Gradle Plugin is not cached, use an online first build. After dependencies are cached, `--offline` can be used.

The APK is created at:

`app/build/outputs/apk/debug/app-debug.apk`

A convenience build script is also provided:

```bash
# Build the debug APK using the Termux environment checks in the repository script.
./build-termux.sh
```

## Root requirements

The editor uses `su` and therefore requires a rooted Android device with Magisk/root access.

The default save path is:

`/data/user/0/pl.idreams.Dino/shared_prefs/pl.idreams.Dino.v2.playerprefs.xml`

The loader first searches the default path, the `dataDir` reported by `dumpsys package pl.idreams.Dino`, and `/data/data/...`. It accepts any XML containing a `<string>` element named `save`.

The game is force-stopped before reading and writing the save.

## Save safety

The editor never launches the game until the newly written file has been read back and successfully decoded.

Before saving, a timestamped backup is created beside the original file:

`<save>.bak.YYYYMMDD_HHMMSS`

If writing fails, the original file is protected by the temporary-file + atomic-rename workflow.

**Always keep an independent backup before editing a new save.**
