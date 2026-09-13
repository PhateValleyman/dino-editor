#!/usr/bin/env bash
# ============================================================================
#  Dino Park (pl.idreams.Dino) — INTERAKTIVNÍ TUI SAVE EDITOR (v3.0)
#  Autor: Gemini CLI / Claude pro Jonáše
#
#  VLASTNOSTI:
#  - Šipky (nahoru/dolů) pro navigaci, ENTER pro výběr.
#  - Listování dinosaurů rozdělených podle klecí.
#  - Detailní úprava každého dinosaura zvlášť.
#  - Robustní XML/JSON zpracování.
# ============================================================================

set -uo pipefail

PKG="pl.idreams.Dino"
SAVE_FILENAME="pl.idreams.Dino.v2.playerprefs.xml"
DEFAULT_PATH="/data/data/${PKG}/shared_prefs/${SAVE_FILENAME}"

# --- Barvy a ANSI kódy --------------------------------------------------
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
C_RED='\033[31m'; C_CYAN='\033[36m'; C_DIM='\033[2m'; C_INV='\033[7m'
HIDE_CURSOR='\033[?25l'; SHOW_CURSOR='\033[?25h'

info()  { echo -e "${C_CYAN}$*${C_RESET}"; }
ok()    { echo -e "${C_GREEN}$*${C_RESET}"; }
warn()  { echo -e "${C_YELLOW}$*${C_RESET}"; }
err()   { echo -e "${C_RED}$*${C_RESET}"; }

# --- Kontrola závislostí -------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    err "python3 nenalezen. Nainstaluj ho prosím."
    exit 1
fi

# --- Detekce souboru -----------------------------------------------------
XML_PATH="${1:-}"
if [ -z "$XML_PATH" ] && [ -f "$DEFAULT_PATH" ]; then XML_PATH="$DEFAULT_PATH"; fi
if [ -z "$XML_PATH" ]; then
    FOUND=$(find . -maxdepth 3 -iname "$SAVE_FILENAME" 2>/dev/null | head -n1)
    [ -n "$FOUND" ] && XML_PATH="$(realpath "$FOUND")"
fi
if [ -z "$XML_PATH" ] || [ ! -f "$XML_PATH" ]; then
    err "Save soubor nenalezen."
    exit 1
fi

WORKDIR=$(mktemp -d)
WORK_JSON="$WORKDIR/save.json"
ENGINE="$WORKDIR/engine.py"
DIRTY=0

cleanup() { echo -ne "$SHOW_CURSOR"; rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ============================================================================
#  PYTHON ENGINE (Rozšířený pro TUI potřeby)
# ============================================================================
cat > "$ENGINE" << 'PYEOF'
import sys, json, base64, urllib.parse, re, os

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def decode_val(raw):
    b64 = urllib.parse.unquote(raw)
    padded = b64 + '=' * (-len(b64) % 4)
    return json.loads(base64.b64decode(padded))

def encode_val(data):
    j = json.dumps(data, separators=(', ', ': '))
    b64 = base64.b64encode(j.encode('utf-8')).decode('ascii')
    return urllib.parse.quote(b64, safe='')

def cmd_decode(xml_path, json_out):
    with open(xml_path, 'r', encoding='utf-8') as f:
        xml = f.read()
    m = re.search(r'<string name="save">(.*?)</string>', xml)
    if not m: sys.exit(1)
    data = decode_val(m.group(1))
    save_json(json_out, data)
    print("OK")

def cmd_encode(xml_path, json_in, xml_out):
    with open(xml_path, 'r', encoding='utf-8') as f:
        xml = f.read()
    m = re.search(r'<string name="save">(.*?)</string>', xml)
    if not m: sys.exit(1)
    data = load_json(json_in)
    encoded = encode_val(data)
    new_xml = xml[:m.start(1)] + encoded + xml[m.end(1):]
    with open(xml_out, 'w', encoding='utf-8') as f:
        f.write(new_xml)
    print("OK")

def cmd_summary(json_path):
    d = load_json(json_path)
    c = d.get('_Cages', {})
    total = sum(len(x.get('_Dinos', [])) for x in c.values())
    print(f"Hráč: {d.get('_PlayerName','???')} | Dinosauři: {total} | Mince: {d.get('_CoinsNo',0):,}")

def cmd_get_currencies(json_path):
    d = load_json(json_path)
    keys = ["_CoinsNo", "_BillsNo", "_StonesNo", "_LikesNo", "_XPNum", "_MultiDigToolsNo", "_MultiDig2ToolsNo", "_NumGoldenPickaxe", "_MultiDigGemsNo", "_MultiDig2GemsNo", "_IncubatedEggsNo"]
    for k in keys:
        print(f"{k}:{d.get(k, 0)}")

def cmd_get_advanced(json_path):
    d = load_json(json_path)
    keys = ["_BankLevel", "_TicketBoothLevel", "_ArenaPlayerRank", "_ArenaMultiplayerRating", "_NumMultiplayerWins", "_NumTournamentWins"]
    for k in keys:
        print(f"{k}:{d.get(k, 0)}")

def cmd_fill_all_bones(json_path):
    d = load_json(json_path)
    n = 0
    for chest in d.get('_Chests', {}).values():
        idx = chest.get('_ReconstructionBonesIndex', {})
        bones = chest.setdefault('_Bones', {})
        for bone_name, needed in idx.items():
            bones[bone_name] = max(needed, bones.get(bone_name, 0), 999)
            n += 1
    save_json(json_path, d)
    print(f"OK:{n}")

def cmd_get_cages(json_path):
    d = load_json(json_path)
    cages = d.get('_Cages', {})
    for cid, cage in cages.items():
        lvl = cage.get('_CurrentLevel', 0)
        print(f"CAGE:{cid}:{lvl}")
        for i, dino in enumerate(cage.get('_Dinos', [])):
            spec = "UNICORN" if dino.get('_Special') else "NORMAL"
            print(f"DINO:{cid}:{i}:{dino.get('_Level')}:{spec}:{dino.get('_ID')}")

def cmd_update_cage(json_path, cage_id, value):
    d = load_json(json_path)
    if cage_id in d.get('_Cages', {}):
        d['_Cages'][cage_id]['_CurrentLevel'] = int(value)
        save_json(json_path, d)
        print("OK")

def cmd_get_dino(json_path, cage_id, index):
    d = load_json(json_path)
    dino = d['_Cages'][cage_id]['_Dinos'][int(index)]
    print(json.dumps(dino))

def cmd_update_dino(json_path, cage_id, index, key, value):
    d = load_json(json_path)
    dino = d['_Cages'][cage_id]['_Dinos'][int(index)]
    if key == '_Special':
        dino[key] = (value == 'True')
    else:
        dino[key] = int(value)
    save_json(json_path, d)
    print("OK")

def cmd_set_val(json_path, key, val):
    d = load_json(json_path)
    old = d.get(key)
    if isinstance(old, int) or str(val).isdigit(): d[key] = int(val)
    else: d[key] = val
    save_json(json_path, d)

if __name__ == '__main__':
    cmd = sys.argv[1]
    args = sys.argv[2:]
    globals()[f"cmd_{cmd}"](*args)
PYEOF

run_engine() { python3 "$ENGINE" "$@"; }

# --- TUI Logika ---------------------------------------------------------
echo -ne "$HIDE_CURSOR"
info "Načítám save..."
run_engine decode "$XML_PATH" "$WORK_JSON" >/dev/null || exit 1

# Funkce pro kreslení menu s šipkami
draw_menu() {
    local title="$1"
    local selected="$2"
    shift 2
    local options=("$@")
    
    clear
    echo -e "${C_BOLD}╔══════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BOLD}║   $title${C_RESET}"
    echo -e "${C_BOLD}╚══════════════════════════════════════════╝${C_RESET}"
    run_engine summary "$WORK_JSON"
    echo
    
    for i in "${!options[@]}"; do
        if [ "$i" -eq "$selected" ]; then
            echo -e " > ${C_INV} ${options[$i]} ${C_RESET}"
        else
            echo -e "   ${options[$i]}"
        fi
    done
}

get_input() {
    local key
    IFS= read -rn1 -s key
    if [[ $key == $'\e' ]]; then
        read -rn2 -s key
        case $key in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
    elif [[ $key == "q" || $key == "b" ]]; then
        echo "BACK"
    fi
}

# --- Moduly -------------------------------------------------------------

edit_resources() {
    local keys=("_CoinsNo" "_BillsNo" "_StonesNo" "_LikesNo" "_XPNum" "_MultiDigToolsNo" "_MultiDig2ToolsNo" "_NumGoldenPickaxe" "_MultiDigGemsNo" "_MultiDig2GemsNo" "_IncubatedEggsNo")
    local labels=("Mince" "Bankovky" "Kameny" "Lajky" "XP" "Dynamity I" "Dynamity II" "Zlaté krumpáče" "Gemy I" "Gemy II" "Vejce v inkubátoru")
    local sel=0
    
    while true; do
        mapfile -t cur_lines < <(run_engine get_currencies "$WORK_JSON")
        local options=()
        for i in "${!labels[@]}"; do
            val=$(echo "${cur_lines[$i]}" | cut -d: -f2)
            [[ "$val" =~ ^[0-9]+$ ]] && val_fmt=$(printf "%'d" "$val") || val_fmt="$val"
            options+=("${labels[$i]}: ${C_GREEN}${val_fmt}${C_RESET}")
        done

        draw_menu "ZDROJE A SPOTŘEBNÍ VĚCI" "$sel" "${options[@]}" "Zpět"
        input=$(get_input)
        case "$input" in
            UP) ((sel--)); [ $sel -lt 0 ] && sel=$((${#labels[@]})) ;;
            DOWN) ((sel++)); [ $sel -gt ${#labels[@]} ] && sel=0 ;;
            ENTER)
                [ "$sel" -eq "${#labels[@]}" ] && return
                read -rp "Nová hodnota pro ${labels[$sel]}: " val
                run_engine set_val "$WORK_JSON" "${keys[$sel]}" "$val"
                DIRTY=1 ;;
            BACK) return ;;
        esac
    done
}

edit_advanced() {
    local keys=("_BankLevel" "_TicketBoothLevel" "_ArenaPlayerRank" "_ArenaMultiplayerRating" "_NumMultiplayerWins" "_NumTournamentWins")
    local labels=("Úroveň banky" "Úroveň pokladny" "Rank v Aréně" "Rating v Aréně" "Výhry v MP" "Výhry v turnaji")
    local sel=0
    
    while true; do
        mapfile -t adv_lines < <(run_engine get_advanced "$WORK_JSON")
        local options=()
        for i in "${!labels[@]}"; do
            val=$(echo "${adv_lines[$i]}" | cut -d: -f2)
            options+=("${labels[$i]}: ${C_YELLOW}${val}${C_RESET}")
        done

        draw_menu "STAVBY A STATISTIKY ARÉNY" "$sel" "${options[@]}" "Zpět"
        input=$(get_input)
        case "$input" in
            UP) ((sel--)); [ $sel -lt 0 ] && sel=$((${#labels[@]})) ;;
            DOWN) ((sel++)); [ $sel -gt ${#labels[@]} ] && sel=0 ;;
            ENTER)
                [ "$sel" -eq "${#labels[@]}" ] && return
                warn "Pozor: Úrovně budov nad 6/7 mohou hru zaseknout!"
                read -rp "Nová hodnota pro ${labels[$sel]}: " val
                run_engine set_val "$WORK_JSON" "${keys[$sel]}" "$val"
                DIRTY=1 ;;
            BACK) return ;;
        esac
    done
}

manage_cage() {
    local cid="$1"
    local lvl="$2"
    local sel=0
    
    while true; do
        draw_menu "KLEC: $cid" "$sel" "Úroveň klece: $lvl" "Zpět"
        input=$(get_input)
        case "$input" in
            UP) ((sel--)); [ $sel -lt 0 ] && sel=1 ;;
            DOWN) ((sel++)); [ $sel -gt 1 ] && sel=0 ;;
            ENTER)
                case "$sel" in
                    0) 
                        read -rp "Nová úroveň klece: " v
                        run_engine update_cage "$WORK_JSON" "$cid" "$v"
                        DIRTY=1; return ;;
                    1) return ;;
                esac ;;
            BACK) return ;;
        esac
    done
}

manage_dino() {
    local cid="$1"
    local idx="$2"
    local sel=0
    
    while true; do
        dino_raw=$(run_engine get_dino "$WORK_JSON" "$cid" "$idx")
        lvl=$(echo "$dino_raw" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['_Level'])")
        spec=$(echo "$dino_raw" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['_Special'])")
        
        draw_menu "DINO: $cid [Index $idx]" "$sel" "Level: $lvl" "Unicorn: $spec" "Max Boosts (999)" "Zpět"
        
        input=$(get_input)
        case "$input" in
            UP) ((sel--)); [ $sel -lt 0 ] && sel=3 ;;
            DOWN) ((sel++)); [ $sel -gt 3 ] && sel=0 ;;
            ENTER)
                case "$sel" in
                    0) read -rp "Nový Level (1-6): " v; run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_Level" "$v"; DIRTY=1 ;;
                    1) [ "$spec" == "True" ] && v="False" || v="True"; run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_Special" "$v"; DIRTY=1 ;;
                    2) 
                        run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_BoostPower" "999"
                        run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_BoostHP" "999"
                        run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_BoostSpeed" "999"
                        run_engine update_dino "$WORK_JSON" "$cid" "$idx" "_BoostDefense" "999"
                        DIRTY=1; ok "Boosty nastaveny."; sleep 1 ;;
                    3) return ;;
                esac ;;
            BACK) return ;;
        esac
    done
}

browse_dinos() {
    local sel=0
    while true; do
        mapfile -t lines < <(run_engine get_cages "$WORK_JSON")
        local options=()
        local data=()
        
        options+=("${C_YELLOW}${C_BOLD}>>> DOPLNIT VŠECHNY KOSTI (MAX) <<<${C_RESET}")
        data+=("FILL_BONES")

        for line in "${lines[@]}"; do
            if [[ $line == CAGE:* ]]; then
                # CAGE:cid:lvl
                IFS=':' read -r _ cid lvl <<< "$line"
                options+=("${C_BOLD}=== Klec: $cid [Lvl $lvl] ===${C_RESET}")
                data+=("CAGE:$cid:$lvl")
            else
                # DINO:cid:idx:lvl:spec:id
                IFS=':' read -r _ cid idx lvl spec did <<< "$line"
                icon="🦕" ; [ "$spec" == "UNICORN" ] && icon="🦄"
                options+=("  $icon Lvl $lvl | $did")
                data+=("DINO:$cid:$idx")
            fi
        done
        
        draw_menu "PROHLÍŽEČ DINOSAURŮ" "$sel" "${options[@]}" "Zpět"
        
        input=$(get_input)
        case "$input" in
            UP) ((sel--)); [ $sel -lt 0 ] && sel=$((${#options[@]})) ;;
            DOWN) ((sel++)); [ $sel -gt ${#options[@]} ] && sel=0 ;;
            ENTER)
                [ "$sel" -eq "${#options[@]}" ] && return
                d="${data[$sel]}"
                case "$d" in
                    FILL_BONES)
                        res=$(run_engine fill_all_bones "$WORK_JSON")
                        count=$(echo "$res" | cut -d: -f2)
                        ok "Doplněno $count typů kostí."; DIRTY=1; sleep 1 ;;
                    CAGE:*)
                        IFS=':' read -r _ cid lvl <<< "$d"
                        manage_cage "$cid" "$lvl" ;;
                    DINO:*)
                        IFS=':' read -r _ cid idx <<< "$d"
                        manage_dino "$cid" "$idx" ;;
                esac ;;
            BACK) return ;;
        esac
    done
}

# --- Hlavní smyčka -------------------------------------------------------
main_sel=0
while true; do
    opts=("Zdroje a spotřební věci" "Prohlížet dinosaury" "Stavby a Aréna" "ULOŽIT ZMĚNY" "Ukončit")
    draw_menu "DINO PARK EDITOR v3.3" "$main_sel" "${opts[@]}"
    
    input=$(get_input)
    case "$input" in
        UP) ((main_sel--)); [ $main_sel -lt 0 ] && main_sel=4 ;;
        DOWN) ((main_sel++)); [ $main_sel -gt 4 ] && main_sel=0 ;;
        ENTER)
            case "$main_sel" in
                0) edit_resources ;;
                1) browse_dinos ;;
                2) edit_advanced ;;
                3) 
                    info "Ukládám..."
                    bak="${XML_PATH}.bak.$(date +%H%M%S)"
                    cp "$XML_PATH" "$bak"
                    run_engine encode "$XML_PATH" "$WORK_JSON" "$XML_PATH"
                    DIRTY=0; ok "Uloženo. Záloha: $(basename "$bak")"; sleep 1 ;;
                4) exit 0 ;;
            esac ;;
    esac
done
