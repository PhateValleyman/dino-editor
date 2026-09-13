package cz.umbrellacorp.dinoeditor;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.text.InputType;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends Activity {

    private static final String PKG = "pl.idreams.Dino";
    private static final String ACTIVITY = PKG + "/com.unity3d.player.UnityPlayerActivity";
    private static final String DEFAULT_PATH = "/data/user/0/" + PKG + "/shared_prefs/pl.idreams.Dino.v2.playerprefs.xml";

    private EditText editPath;
    private TextView txtLog;

    private String currentXml;
    private JSONObject currentData;
    private String currentPath;
    private final AtomicBoolean operationRunning = new AtomicBoolean(false);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        editPath = findViewById(R.id.editPath);
        txtLog = findViewById(R.id.txtLog);

        findViewById(R.id.btnLoad).setOnClickListener(v -> loadSave());
        findViewById(R.id.btnSummary).setOnClickListener(v -> showSummary());
        findViewById(R.id.btnCurrency).setOnClickListener(v -> menuCurrency());
        findViewById(R.id.btnDinos).setOnClickListener(v -> menuDinos());
        findViewById(R.id.btnCages).setOnClickListener(v -> menuCages());
        findViewById(R.id.btnUnlocks).setOnClickListener(v -> menuUnlocks());
        findViewById(R.id.btnLevels).setOnClickListener(v -> menuLevels());
        findViewById(R.id.btnArena).setOnClickListener(v -> menuArena());
        findViewById(R.id.btnBones).setOnClickListener(v -> {
            if (!requireLoaded() || operationRunning.get()) return;
            try {
                log(DinoEngine.fillBones(currentData));
            } catch (Exception e) {
                log("CHYBA: " + e.getMessage());
            }
        });
        findViewById(R.id.btnSave).setOnClickListener(v -> saveAndLaunch());
    }

    private void log(String msg) {
        txtLog.setText(msg == null ? "" : msg);
    }

    private boolean requireLoaded() {
        if (currentData == null || currentXml == null || currentPath == null) {
            log("Nejdřív načti save (tlačítko 'Načíst save').");
            return false;
        }
        return true;
    }

    private boolean beginOperation(String message) {
        if (!operationRunning.compareAndSet(false, true)) {
            log("Počkej na dokončení předchozí operace.");
            return false;
        }
        log(message);
        return true;
    }

    private void endOperation() {
        operationRunning.set(false);
    }

    private void loadSave() {
        if (!beginOperation("Načítám...")) return;

        String requestedPath = editPath.getText().toString().trim();
        if (requestedPath.isEmpty() || requestedPath.indexOf('\n') >= 0 || requestedPath.indexOf('\r') >= 0) {
            requestedPath = DEFAULT_PATH;
        }
        final String initialPath = requestedPath;

        new Thread(() -> {
            try {
                RootShell.forceStopApp(PKG);

                String path = initialPath;
                String detected = RootShell.findPlayerPrefs(PKG);
                if (detected != null && initialPath.equals(DEFAULT_PATH)) {
                    path = detected;
                } else if (!RootShell.fileExists(path)) {
                    throw new IOException("PlayerPrefs se save polem nebyl nalezen: " + path);
                }

                String xml = RootShell.readFile(path);
                JSONObject data = DinoEngine.decode(xml);

                final String loadedPath = path;
                currentXml = xml;
                currentData = data;
                currentPath = path;
                runOnUiThread(() -> {
                    editPath.setText(loadedPath);
                    log("Save načten.\nSoubor: " + loadedPath + "\n\n" + safeSummary());
                });
            } catch (Exception e) {
                final String msg = e.getMessage();
                runOnUiThread(() -> log("CHYBA při načítání: " + msg));
            } finally {
                runOnUiThread(this::endOperation);
            }
        }).start();
    }

    private String safeSummary() {
        try {
            return DinoEngine.summary(currentData);
        } catch (Exception e) {
            return "(chyba přehledu: " + e.getMessage() + ")";
        }
    }

    private void showSummary() {
        if (!requireLoaded()) return;
        log(safeSummary());
    }

    private static String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private void saveAndLaunch() {
        if (!requireLoaded() || !beginOperation("Ukládám...")) return;

        // Use the path that was actually loaded, not a path changed in the text field afterwards.
        final String path = currentPath;
        final String xmlSnapshot = currentXml;
        final JSONObject dataSnapshot;
        try {
            dataSnapshot = new JSONObject(currentData.toString());
        } catch (Exception e) {
            endOperation();
            log("CHYBA: nelze vytvořit snapshot save: " + e.getMessage());
            return;
        }

        new Thread(() -> {
            try {
                RootShell.forceStopApp(PKG);

                String backupPath = path + ".bak.$(date +%Y%m%d_%H%M%S)";
                RootShell.Result backup = RootShell.run(
                        "backup=" + quote(backupPath) +
                                "; cp " + quote(path) + " \"$backup\" && test -s \"$backup\"");
                if (backup.exitCode != 0) {
                    throw new IOException("Záloha selhala: " + backup.stderr.trim());
                }

                String newXml = DinoEngine.encode(xmlSnapshot, dataSnapshot);
                RootShell.writeFile(path, newXml);

                // Verify the file can be read and decoded before launching the game.
                String verifyXml = RootShell.readFile(path);
                DinoEngine.decode(verifyXml);

                currentXml = newXml;
                currentData = dataSnapshot;
                RootShell.launchApp(ACTIVITY);
                runOnUiThread(() -> log("Uloženo a ověřeno. Záloha: " + backupPath + "\nHra spuštěna."));
            } catch (Exception e) {
                final String msg = e.getMessage();
                runOnUiThread(() -> log("CHYBA při ukládání: " + msg));
            } finally {
                runOnUiThread(this::endOperation);
            }
        }).start();
    }

    // ---- měna a zdroje --------------------------------------------------

    private static final String[][] CURRENCY_FIELDS = {
            {"Mince", "_CoinsNo"}, {"Bankovky", "_BillsNo"}, {"Kameny", "_StonesNo"},
            {"Lajky", "_LikesNo"}, {"XP", "_XPNum"}, {"Dynamity I", "_MultiDigToolsNo"},
            {"Dynamity II", "_MultiDig2ToolsNo"}, {"Zlaté krumpáče", "_NumGoldenPickaxe"},
            {"Gemy I", "_MultiDigGemsNo"}, {"Gemy II", "_MultiDig2GemsNo"},
            {"Vejce v inkubátoru", "_IncubatedEggsNo"},
    };

    private void menuCurrency() {
        if (!requireLoaded()) return;
        String[] labels = new String[CURRENCY_FIELDS.length];
        for (int i = 0; i < labels.length; i++) {
            labels[i] = CURRENCY_FIELDS[i][0] + ": " + currentData.opt(CURRENCY_FIELDS[i][1]);
        }
        new AlertDialog.Builder(this).setTitle("Měna a zdroje")
                .setItems(labels, (dialog, which) -> promptCurrencyValue(CURRENCY_FIELDS[which][0], CURRENCY_FIELDS[which][1]))
                .setNegativeButton("Zpět", null).show();
    }

    private void promptCurrencyValue(String label, String field) {
        final EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED);
        new AlertDialog.Builder(this).setTitle(label).setView(input)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.setCurrency(currentData, field, input.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }

    // ---- dinosauři ------------------------------------------------------

    private void menuDinos() {
        if (!requireLoaded()) return;
        try {
            String list = DinoEngine.listDinos(currentData);
            if (list.startsWith("Žádní")) { log(list); return; }
            String[] lines = list.split("\n");
            new AlertDialog.Builder(this).setTitle("🦕 Dinosauři")
                    .setItems(lines, (dialog, which) -> editDino(which))
                    .setNegativeButton("Zpět", null).show();
        } catch (Exception e) { log("CHYBA: " + e.getMessage()); }
    }

    private void menuCages() {
        if (!requireLoaded()) return;
        try {
            final String list = DinoEngine.listCages(currentData);
            if (list.isEmpty()) { log("Žádné klece."); return; }
            final String[] cages = list.split("\n");
            new AlertDialog.Builder(this).setTitle("Úrovně klecí")
                    .setItems(cages, (dialog, which) -> {
                        String[] parts = cages[which].split("\\|", 3);
                        if (parts.length < 3) { log("CHYBA: neplatný záznam klece."); return; }
                        promptCageLevel(parts[0].trim(), parts[2].trim(), parts[1].trim());
                    }).setNegativeButton("Zpět", null).show();
        } catch (Exception e) { log("CHYBA: " + e.getMessage()); }
    }

    private void promptCageLevel(final String cageId, String currentLevel, String dinoName) {
        final EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setText(currentLevel);
        new AlertDialog.Builder(this).setTitle("Nová úroveň klece " + dinoName).setView(input)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.setCageLevel(currentData, cageId, input.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }

    private void editDino(final int idx) {
        String[] actions = {"Změnit level", "Přepnout UNICORN", "Nastavit boosty"};
        new AlertDialog.Builder(this).setTitle("Úprava dino #" + idx)
                .setItems(actions, (dialog, which) -> {
                    if (which == 0) promptDinoLevel(idx);
                    else if (which == 1) toggleDinoSpecial(idx);
                    else promptDinoBoost(idx);
                }).setNegativeButton("Zpět", null).show();
    }

    private void promptDinoLevel(final int idx) {
        final EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        new AlertDialog.Builder(this).setTitle("Nový level (max 6)").setView(input)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.dinoSetLevel(currentData, idx, input.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }

    private void toggleDinoSpecial(final int idx) {
        new AlertDialog.Builder(this).setTitle("UNICORN?")
                .setItems(new String[]{"Ano", "Ne"}, (d, which) -> {
                    try { log(DinoEngine.dinoSetSpecial(currentData, idx, which == 0)); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).show();
    }

    private void promptDinoBoost(final int idx) {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(32, 16, 32, 16);
        final EditText p = addLabeledInput(layout, "BoostPower (prázdné = beze změny)");
        final EditText h = addLabeledInput(layout, "BoostHP (prázdné = beze změny)");
        final EditText s = addLabeledInput(layout, "BoostSpeed (prázdné = beze změny)");
        final EditText df = addLabeledInput(layout, "BoostDefense (prázdné = beze změny)");
        new AlertDialog.Builder(this).setTitle("Boosty dino #" + idx).setView(layout)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.dinoSetBoost(currentData, idx, p.getText().toString(), h.getText().toString(), s.getText().toString(), df.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }

    private EditText addLabeledInput(LinearLayout parent, String hint) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED);
        parent.addView(e);
        return e;
    }

    // ---- odemčené funkce --------------------------------------------------

    private void menuUnlocks() {
        if (!requireLoaded()) return;
        final String[] fields = DinoEngine.UNLOCK_FIELDS;
        boolean[] checked = new boolean[fields.length];
        for (int i = 0; i < fields.length; i++) checked[i] = currentData.optBoolean(fields[i], false);
        new AlertDialog.Builder(this).setTitle("Odemčené funkce")
                .setMultiChoiceItems(fields, checked, (dialog, which, isChecked) -> {
                    try { currentData.put(fields[which], isChecked); } catch (Exception ignored) { }
                }).setPositiveButton("Hotovo", (d, w) -> log("Odemčené funkce upraveny.")).show();
    }

    // ---- úrovně -------------------------------------------------------

    private void menuLevels() {
        if (!requireLoaded()) return;
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(32, 16, 32, 16);
        final EditText bank = addLabeledInput(layout, "Level banky (max 6)");
        final EditText ticket = addLabeledInput(layout, "Level pokladny (max 4)");
        bank.setText(String.valueOf(currentData.opt("_BankLevel")));
        ticket.setText(String.valueOf(currentData.opt("_TicketBoothLevel")));
        new AlertDialog.Builder(this).setTitle("Úrovně banky/pokladny").setView(layout)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.setLevelsSafe(currentData, bank.getText().toString(), ticket.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }

    // ---- aréna --------------------------------------------------------

    private void menuArena() {
        if (!requireLoaded()) return;
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(32, 16, 32, 16);
        final EditText rank = addLabeledInput(layout, "Arena rank");
        final EditText rating = addLabeledInput(layout, "Arena rating");
        final EditText wt = addLabeledInput(layout, "Výhry turnaj");
        final EditText wm = addLabeledInput(layout, "Výhry MP");
        final EditText lm = addLabeledInput(layout, "Prohry MP");
        final EditText ls = addLabeledInput(layout, "Série proher");
        new AlertDialog.Builder(this).setTitle("Aréna").setView(layout)
                .setPositiveButton("OK", (d, w) -> {
                    try { log(DinoEngine.setArena(currentData, rank.getText().toString(), rating.getText().toString(), wt.getText().toString(), wm.getText().toString(), lm.getText().toString(), ls.getText().toString())); }
                    catch (Exception e) { log("CHYBA: " + e.getMessage()); }
                }).setNegativeButton("Zrušit", null).show();
    }
}
