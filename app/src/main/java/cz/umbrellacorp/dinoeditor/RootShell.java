package cz.umbrellacorp.dinoeditor;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** Root shell helpers used by the editor. */
public final class RootShell {

    private RootShell() {
    }

    public static class Result {
        public final int exitCode;
        public final String stdout;
        public final String stderr;

        Result(int exitCode, String stdout, String stderr) {
            this.exitCode = exitCode;
            this.stdout = stdout;
            this.stderr = stderr;
        }
    }

    private static Thread drainAsync(final InputStream in, final ByteArrayOutputStream sink) {
        Thread t = new Thread(() -> {
            try {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) {
                    synchronized (sink) {
                        sink.write(buf, 0, n);
                    }
                }
            } catch (IOException ignored) {
                // The process exit code remains authoritative for command failures.
            }
        }, "DinoRootShell");
        t.start();
        return t;
    }

    private static String quote(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    public static Result run(String shellCommand) {
        try {
            Process p = new ProcessBuilder("su", "-c", shellCommand).start();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ByteArrayOutputStream err = new ByteArrayOutputStream();
            Thread outThread = drainAsync(p.getInputStream(), out);
            Thread errThread = drainAsync(p.getErrorStream(), err);
            int code = p.waitFor();
            outThread.join();
            errThread.join();
            return new Result(code,
                    new String(out.toByteArray(), StandardCharsets.UTF_8),
                    new String(err.toByteArray(), StandardCharsets.UTF_8));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new Result(-1, "", "Příkaz byl přerušen.");
        } catch (Exception e) {
            return new Result(-1, "", "Nepodařilo se spustit 'su': " + e.getMessage());
        }
    }

    /** Checks whether a root-visible regular file exists. */
    public static boolean fileExists(String path) {
        return run("test -f " + quote(path)).exitCode == 0;
    }

    /**
     * Finds a Dino Park PlayerPrefs XML containing the actual save field.
     * The package dump supplies the real dataDir, which also covers Android
     * installations using /data/user/0 or a different shared_prefs filename.
     */
    public static String findPlayerPrefs(String pkg) {
        String command =
                "data_dir=$(dumpsys package " + quote(pkg) +
                " 2>/dev/null | sed -n 's/^[[:space:]]*dataDir=//p' | head -n 1); " +
                "for base in /data/user/0/" + quote(pkg) + "/shared_prefs " +
                "\"$data_dir/shared_prefs\" /data/data/" + quote(pkg) + "/shared_prefs; do " +
                "[ -d \"$base\" ] || continue; " +
                "for f in \"$base\"/*.xml; do " +
                "[ -f \"$f\" ] || continue; " +
                "grep -q 'name=\"save\"' \"$f\" 2>/dev/null && " +
                "printf '%s\\n' \"$f\" && exit 0; " +
                "done; done; exit 1";

        Result r = run(command);
        if (r.exitCode != 0) return null;
        String output = r.stdout.trim();
        if (output.isEmpty()) return null;
        return output.split("\\r?\\n", 2)[0].trim();
    }

    public static String readFile(String path) throws IOException {
        Result r = run("cat " + quote(path));
        if (r.exitCode != 0) {
            throw new IOException("Čtení selhalo (kód " + r.exitCode + "): " + r.stderr.trim());
        }
        return r.stdout;
    }

    /**
     * Writes UTF-8 content through a temporary file in the same directory.
     *
     * The original PlayerPrefs metadata is captured before writing and applied
     * to the temporary file before the atomic rename. This is important on
     * Android: replacing an app-private file with a root-created file can leave
     * the new file owned by root, making the game unable to read its own save.
     *
     * The operation fails safely if the original metadata cannot be read.
     */
    public static void writeFile(String path, String content) throws IOException {
        if (content == null || content.isEmpty()) {
            throw new IOException("Nelze zapsat prázdný obsah save.");
        }

        String tempPath = path + ".tmp." + Long.toHexString(System.nanoTime());
        String command =
                "set -- $(stat -c '%u %g %a' " + quote(path) + ") && " +
                "[ $# -eq 3 ] && " +
                "uid=$1; gid=$2; mode=$3; " +
                "cat > " + quote(tempPath) + " && " +
                "test -s " + quote(tempPath) + " && " +
                "chown \"$uid:$gid\" " + quote(tempPath) + " && " +
                "chmod \"$mode\" " + quote(tempPath) + " && " +
                "mv -f " + quote(tempPath) + " " + quote(path);

        try {
            Process p = new ProcessBuilder("su", "-c", command).start();
            OutputStream os = p.getOutputStream();
            os.write(content.getBytes(StandardCharsets.UTF_8));
            os.flush();
            os.close();

            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ByteArrayOutputStream err = new ByteArrayOutputStream();
            Thread outThread = drainAsync(p.getInputStream(), out);
            Thread errThread = drainAsync(p.getErrorStream(), err);
            int code = p.waitFor();
            outThread.join();
            errThread.join();

            if (code != 0) {
                String detail = new String(err.toByteArray(), StandardCharsets.UTF_8).trim();
                if (detail.isEmpty()) {
                    detail = "Nelze zachovat vlastníka/práva původního souboru.";
                }
                throw new IOException("Zápis selhal (kód " + code + "): " + detail);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Zápis přerušen.");
        } finally {
            // Remove the temporary file if the atomic rename did not happen.
            run("rm -f " + quote(tempPath));
        }
    }

    public static void forceStopApp(String pkg) {
        run("am force-stop " + quote(pkg));
    }

    public static void launchApp(String pkgAndActivity) {
        Result result = run("am start -n " + quote(pkgAndActivity));
        if (result.exitCode != 0) {
            throw new IllegalStateException("Spuštění aplikace selhalo: " + result.stderr.trim());
        }
    }
}
