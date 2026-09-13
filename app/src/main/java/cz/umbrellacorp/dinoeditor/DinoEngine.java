package cz.umbrellacorp.dinoeditor;

import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Save codec and editor operations for the Dino Park PlayerPrefs save.
 *
 * The save value is URL-encoded Base64 containing UTF-8 JSON inside the
 * PlayerPrefs XML. The JSON structure is intentionally preserved; only fields
 * changed by an editor operation are modified.
 */
public final class DinoEngine {

    private DinoEngine() {
    }

    private static final Map<String, String> DINO_NAMES = new HashMap<>();

    static {
        DINO_NAMES.put("Dino9", "Smilodon");
    }

    public static final String[] UNLOCK_FIELDS = {
            "_TopPanelUnlocked", "_ExpeditionUnlocked", "_IncubatorUnlocked",
            "_TrashBestiaryUnlocked", "_MultiDigUnlocked", "_MultiDigSpecialUnlocked",
            "_ArenaTournamentUnlocked", "_DressRoomUnlocked", "_ArenaUnlocked",
            "_ArenaMultiplayerUnlocked", "_PhotoBoothUnlocked", "_UndegroundUnlocked",
            "_FactoryUnlocked", "_ArenaTrainingCampUnlocked", "_FbLiked",
            "_BestiaryVisited", "HasAnyTotem"
    };

    private static final Pattern SAVE_FIELD = Pattern.compile(
            "<string\\s+name=\\\"save\\\">(.*?)</string>", Pattern.DOTALL);

    public static final class DinoRef {
        public final String cageId;
        public final JSONObject dino;

        DinoRef(String cageId, JSONObject dino) {
            this.cageId = cageId;
            this.dino = dino;
        }
    }

    // ---- XML <-> JSON blob --------------------------------------------

    public static JSONObject decode(String xml) throws Exception {
        Matcher m = findSaveField(xml);
        String raw = m.group(1);
        if (raw == null || raw.trim().isEmpty()) {
            throw new Exception("Pole 'save' je prázdné.");
        }

        String b64 = URLDecoder.decode(raw, "UTF-8").trim();
        StringBuilder padded = new StringBuilder(b64);
        while (padded.length() % 4 != 0) {
            padded.append('=');
        }

        final byte[] bytes;
        try {
            bytes = Base64.decode(padded.toString(), Base64.DEFAULT);
        } catch (IllegalArgumentException e) {
            throw new Exception("Pole 'save' obsahuje neplatný Base64 blob.", e);
        }

        try {
            return new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        } catch (JSONException e) {
            throw new Exception("Dekódovaný save není platný JSON.", e);
        }
    }

    public static String encode(String xml, JSONObject data) throws Exception {
        Matcher m = findSaveField(xml);
        String json = data.toString();
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        String b64 = Base64.encodeToString(bytes, Base64.NO_WRAP);
        String encoded = URLEncoder.encode(b64, "UTF-8");
        return xml.substring(0, m.start(1)) + encoded + xml.substring(m.end(1));
    }

    private static Matcher findSaveField(String xml) throws Exception {
        if (xml == null) {
            throw new Exception("XML save je null.");
        }
        Matcher m = SAVE_FIELD.matcher(xml);
        if (!m.find()) {
            throw new Exception("Pole 'save' nenalezeno v XML.");
        }
        return m;
    }

    // ---- helpers --------------------------------------------------------

    public static List<DinoRef> iterDinos(JSONObject data) throws JSONException {
        List<DinoRef> out = new ArrayList<>();
        JSONObject cages = data.optJSONObject("_Cages");
        if (cages == null) return out;

        Iterator<String> it = cages.keys();
        while (it.hasNext()) {
            String cageId = it.next();
            JSONObject cage = cages.optJSONObject(cageId);
            if (cage == null) continue;

            JSONArray dinos = cage.optJSONArray("_Dinos");
            if (dinos == null) continue;

            for (int i = 0; i < dinos.length(); i++) {
                JSONObject dino = dinos.optJSONObject(i);
                if (dino != null) {
                    out.add(new DinoRef(cageId, dino));
                }
            }
        }
        return out;
    }

    public static String summary(JSONObject d) throws JSONException {
        JSONObject cages = d.optJSONObject("_Cages");
        int cageCount = cages == null ? 0 : cages.length();
        int total = 0;

        if (cages != null) {
            Iterator<String> it = cages.keys();
            while (it.hasNext()) {
                JSONObject cage = cages.optJSONObject(it.next());
                if (cage == null) continue;
                JSONArray dinos = cage.optJSONArray("_Dinos");
                if (dinos != null) total += dinos.length();
            }
        }

        StringBuilder sb = new StringBuilder();
        sb.append("Hráč: ").append(d.optString("_PlayerName", "???")).append('\n');
        sb.append("Mince: ").append(d.opt("_CoinsNo")).append('\n');
        sb.append("Bankovky: ").append(d.opt("_BillsNo")).append('\n');
        sb.append("Prasátko: ").append(d.opt("_PiggyBank")).append('\n');
        sb.append("Kameny: ").append(d.opt("_StonesNo")).append('\n');
        sb.append("Lajky: ").append(d.opt("_LikesNo")).append('\n');
        sb.append("XP: ").append(d.opt("_XPNum")).append('\n');
        sb.append("Level banky: ").append(d.opt("_BankLevel")).append('\n');
        sb.append("Level pokladny: ").append(d.opt("_TicketBoothLevel")).append('\n');
        sb.append("Vejce (inkubátor): ").append(d.opt("_IncubatedEggsNo")).append('\n');
        sb.append("Arena rank: ").append(d.opt("_ArenaPlayerRank")).append('\n');
        sb.append("Arena rating: ").append(d.opt("_ArenaMultiplayerRating")).append('\n');
        sb.append("Počet klecí: ").append(cageCount)
                .append(" (dinosaurů: ").append(total).append(")");
        return sb.toString();
    }

    public static String listDinos(JSONObject data) throws JSONException {
        List<DinoRef> dinos = iterDinos(data);
        if (dinos.isEmpty()) return "Žádní dinosauři.";

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < dinos.size(); i++) {
            DinoRef ref = dinos.get(i);
            JSONObject dn = ref.dino;
            boolean special = dn.optBoolean("_Special", false);
            String dinoId = dn.optString("_ID", "Neznámý");

            sb.append(special ? "🦄 " : "🦕 ")
                    .append('#').append(i + 1)
                    .append("  •  ").append(dinoName(dinoId))
                    .append("  •  Level ").append(dn.opt("_Level"))
                    .append("  •  Klec ").append(dinoName(ref.cageId))
                    .append(special ? "  •  UNICORN" : "")
                    .append('\n');
        }
        return sb.toString().trim();
    }

    public static String listCages(JSONObject data) throws JSONException {
        JSONObject cages = data.optJSONObject("_Cages");
        if (cages == null || cages.length() == 0) return "";

        StringBuilder sb = new StringBuilder();
        Iterator<String> it = cages.keys();
        while (it.hasNext()) {
            String cageId = it.next();
            JSONObject cage = cages.optJSONObject(cageId);
            if (cage == null) continue;

            String dinoId = cage.optString("_DinoID", cageId);
            if (sb.length() > 0) sb.append('\n');
            sb.append(cageId).append(" | ").append(dinoName(dinoId))
                    .append(" | ").append(cage.optInt("_CurrentLevel", 0));
        }
        return sb.toString();
    }

    private static String dinoName(String dinoId) {
        String name = DINO_NAMES.get(dinoId);
        return name == null ? dinoId : name;
    }

    public static String setCageLevel(JSONObject data, String cageId, String levelStr) throws JSONException {
        JSONObject cages = data.optJSONObject("_Cages");
        if (cages == null || !cages.has(cageId)) return "CHYBA: klec neexistuje.";

        final int level;
        try {
            level = Integer.parseInt(levelStr.trim());
        } catch (NumberFormatException e) {
            return "CHYBA: úroveň musí být celé číslo.";
        }
        if (level < 0) return "CHYBA: úroveň nesmí být záporná.";

        JSONObject cage = cages.getJSONObject(cageId);
        Object old = cage.opt("_CurrentLevel");
        cage.put("_CurrentLevel", level);
        return "OK  klec " + cageId + ": " + old + " -> " + level;
    }

    // ---- currency ---------------------------------------------------------

    public static String setCurrency(JSONObject d, String field, String value) throws JSONException {
        final int n;
        try {
            n = Integer.parseInt(value.trim());
        } catch (NumberFormatException e) {
            return "CHYBA: '" + value + "' není celé číslo.";
        }
        if (n < 0) return "CHYBA: hodnota nesmí být záporná.";

        Object old = d.opt(field);
        d.put(field, n);
        return "OK  " + field + ": " + old + " -> " + n;
    }

    // ---- dinos --------------------------------------------------------

    public static String dinoSetLevel(JSONObject d, int idx, String levelStr) throws JSONException {
        List<DinoRef> dinos = iterDinos(d);
        if (idx < 0 || idx >= dinos.size()) return "CHYBA: neplatný index.";

        final int level;
        try {
            level = Integer.parseInt(levelStr.trim());
        } catch (NumberFormatException e) {
            return "CHYBA: '" + levelStr + "' není celé číslo.";
        }
        if (level < 0) return "CHYBA: level nesmí být záporný.";

        JSONObject dino = dinos.get(idx).dino;
        Object old = dino.opt("_Level");
        dino.put("_Level", level);
        String warn = level > 6 ? "\nVAROVÁNÍ: level > 6 může způsobit pád." : "";
        return "OK  dino[" + idx + "] level: " + old + " -> " + level + warn;
    }

    public static String dinoSetSpecial(JSONObject d, int idx, boolean special) throws JSONException {
        List<DinoRef> dinos = iterDinos(d);
        if (idx < 0 || idx >= dinos.size()) return "CHYBA: neplatný index.";
        dinos.get(idx).dino.put("_Special", special);
        return "OK  dino[" + idx + "] _Special = " + special;
    }

    public static String dinoSetBoost(JSONObject d, int idx, String power, String hp,
                                      String speed, String defense) throws JSONException {
        List<DinoRef> dinos = iterDinos(d);
        if (idx < 0 || idx >= dinos.size()) return "CHYBA: neplatný index.";

        JSONObject dino = dinos.get(idx).dino;
        String[] keys = {"_BoostPower", "_BoostHP", "_BoostSpeed", "_BoostDefense"};
        String[] vals = {power, hp, speed, defense};
        StringBuilder problems = new StringBuilder();

        for (int i = 0; i < keys.length; i++) {
            String v = vals[i];
            if (v == null || v.trim().isEmpty() || v.trim().equals("-")) continue;
            try {
                int n = Integer.parseInt(v.trim());
                if (n < 0) {
                    problems.append("\npřeskočeno ").append(keys[i]).append(" (záporná hodnota)");
                } else {
                    dino.put(keys[i], n);
                }
            } catch (NumberFormatException e) {
                problems.append("\npřeskočeno ").append(keys[i])
                        .append(" ('").append(v).append("' není číslo)");
            }
        }
        return "OK  dino[" + idx + "] boosty nastaveny" + problems;
    }

    // ---- bones ------------------------------------------------------------

    public static String fillBones(JSONObject d) throws JSONException {
        JSONObject chests = d.optJSONObject("_Chests");
        int n = 0;
        if (chests != null) {
            Iterator<String> it = chests.keys();
            while (it.hasNext()) {
                JSONObject chest = chests.optJSONObject(it.next());
                if (chest == null) continue;

                JSONObject need = chest.optJSONObject("_ReconstructionBonesIndex");
                if (need == null) continue;

                JSONObject bones = chest.optJSONObject("_Bones");
                if (bones == null) {
                    bones = new JSONObject();
                    chest.put("_Bones", bones);
                }

                Iterator<String> bit = need.keys();
                while (bit.hasNext()) {
                    String bone = bit.next();
                    int needed = need.optInt(bone, 0);
                    int have = bones.optInt(bone, 0);
                    bones.put(bone, Math.max(Math.max(needed, have), 999));
                    n++;
                }
            }
        }
        return "OK  doplněno " + n + " typů kostí";
    }

    // ---- unlocks ------------------------------------------------------

    public static String listUnlocks(JSONObject d) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < UNLOCK_FIELDS.length; i++) {
            boolean val = d.optBoolean(UNLOCK_FIELDS[i], false);
            sb.append(i).append(" | [")
                    .append(val ? "ANO" : "ne ")
                    .append("] ").append(UNLOCK_FIELDS[i]).append('\n');
        }
        return sb.toString().trim();
    }

    public static String toggleUnlock(JSONObject d, int idx) throws JSONException {
        if (idx < 0 || idx >= UNLOCK_FIELDS.length) return "CHYBA: neplatný index.";
        String field = UNLOCK_FIELDS[idx];
        boolean val = !d.optBoolean(field, false);
        d.put(field, val);
        return "OK  " + field + " -> " + val;
    }

    // ---- arena / levels -------------------------------------------------

    public static String setArena(JSONObject d, String rank, String rating, String winsT,
                                   String winsM, String lostM, String lostStrike) throws JSONException {
        int[] vals = new int[6];
        String[] raw = {rank, rating, winsT, winsM, lostM, lostStrike};
        for (int i = 0; i < vals.length; i++) {
            try {
                vals[i] = Integer.parseInt(raw[i].trim());
            } catch (Exception e) {
                return "CHYBA: všechny hodnoty musí být celá čísla.";
            }
            if (vals[i] < 0) return "CHYBA: hodnoty nesmí být záporné.";
        }

        d.put("_ArenaPlayerRank", vals[0]);
        d.put("_ArenaMultiplayerRating", vals[1]);
        d.put("ArenaMultiplayerRating", vals[1]);
        d.put("_NumTournamentWins", vals[2]);
        d.put("NumTournamentWins", vals[2]);
        d.put("_NumMultiplayerWins", vals[3]);
        d.put("_NumMultiplayerLost", vals[4]);
        d.put("_ArenaMultiplayerLostStrike", vals[5]);
        return "OK  arena stats nastaveny";
    }

    public static String setLevelsSafe(JSONObject d, String bankStr, String ticketStr) throws JSONException {
        final int bank;
        final int ticket;
        try {
            bank = Integer.parseInt(bankStr.trim());
            ticket = Integer.parseInt(ticketStr.trim());
        } catch (Exception e) {
            return "CHYBA: obě hodnoty musí být celá čísla.";
        }
        if (bank < 0 || ticket < 0) return "CHYBA: úrovně nesmí být záporné.";

        d.put("_BankLevel", bank);
        d.put("_TicketBoothLevel", ticket);
        String warn = (bank > 6 || ticket > 4)
                ? "\nVAROVÁNÍ: hodnoty nad max (bank<=6, pokladna<=4)."
                : "";
        return "OK  _BankLevel=" + bank + "  _TicketBoothLevel=" + ticket + warn;
    }
}
