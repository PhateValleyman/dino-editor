package cz.valleyman.dinoparkeditor;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Spouští příkazy jako "su -c '<command>'" - stejný mechanismus, jaký
 * jsme používali ručně v Termuxu (žádné nové oprávnění navíc; app se musí
 * nechat schválit v Magisku při prvním spuštění).
 */
public class RootShell {

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

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) {
            bos.write(buf, 0, n);
        }
        return bos.toByteArray();
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
        Result r = run("test -f " + quote(path));
        return r.exitCode == 0;
    }

    /**
     * Finds a Dino Park PlayerPrefs XML containing the actual save field.
     * Android commonly exposes app-private data through /data/user/0, while
     * /data/data may be a compatibility symlink on some devices.
     */
    public static String findPlayerPrefs(String pkg) {
        String command =
                "for base in /data/user/0/" + pkg + "/shared_prefs /data/data/" + pkg + "/shared_prefs; do " +
                "[ -d $base ] || continue; " +
                "for f in $base/*playerprefs*.xml $base/*.xml; do " +
                "[ -f $f ] || continue; " +
                "grep -q '<string name=\"save\">' $f 2>/dev/null && printf '%s\n' $f && exit 0; " +
                "done; done; exit 1";
        Result r = run(command);
        if (r.exitCode != 0) return null;
        String[] lines = r.stdout.trim().split("\\r?\\n");
        return lines.length == 0 || lines[0].trim().isEmpty() ? null : lines[0].trim();
    }

    public static String readFile(String path) throws IOException {
        Result r = run("cat " + quote(path));
        if (r.exitCode != 0) {
            throw new IOException("Čtení selhalo (kód " + r.exitCode + "): " + r.stderr.trim());
        }
        return r.stdout;
    }

    /** Writes the supplied UTF-8 content as root. */
    public static void writeFile(String path, String content) throws IOException {
        try {
            Process p = new ProcessBuilder("su", "-c", "cat > " + quote(path)).start();
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
                throw new IOException("Zápis selhal (kód " + code + "): " +
                        new String(err.toByteArray(), StandardCharsets.UTF_8).trim());
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Zápis přerušen.");
        }
    }

    public static void forceStopApp(String pkg) {
        run("am force-stop " + pkg);
    }

    public static void launchApp(String pkgAndActivity) {
        run("am start -n " + pkgAndActivity);
    }
}
