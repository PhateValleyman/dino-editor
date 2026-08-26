#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  Dino Park (pl.idreams.Dino) — interaktivní save editor
#  Autor: Claude pro Jonáše
#
#  Použití:
#     ./dino_save_editor.sh                              (auto-detekce cesty i balíčku)
#     ./dino_save_editor.sh /cesta/k/playerprefs.xml      (vlastní cesta k save souboru)
#
#  Skript automaticky:
#    - najde save soubor na standardní cestě balíčku (nebo v aktuálním adresáři)
#    - před editací hru ukončí (am force-stop), aby živý proces neprepsal změny
#    - po uložení nabídne hru znovu spustit
#
#  Vyžaduje: python3  (na Termuxu: pkg install python)
#            root přístup pro 'am force-stop' / čtení /data/data/... (běžný su shell)
# ============================================================================

export FZF_DEFAULT_OPTS="--ansi --border --height=80%"

set -uo pipefail

PKG="pl.idreams.Dino"
SAVE_FILENAME="pl.idreams.Dino.v2.playerprefs.xml"
DEFAULT_PATH="/data/data/${PKG}/shared_prefs/${SAVE_FILENAME}"
LAUNCH_ACTIVITY="${PKG}/com.unity3d.player.UnityPlayerActivity"

# --- Barvy pro čitelnost v terminálu -----------------------------------
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
C_RED='\033[31m'; C_CYAN='\033[36m'; C_DIM='\033[2m'
C_MAGENTA='\033[35m'; C_BLUE='\033[34m'; C_WHITE='\033[97m'; C_ORANGE='\033[38;5;208m'

info()  { echo -e "${C_CYAN}$*${C_RESET}"; }
ok()    { echo -e "${C_GREEN}$*${C_RESET}"; }
warn()  { echo -e "${C_YELLOW}$*${C_RESET}"; }
err()   { echo -e "${C_RED}$*${C_RESET}"; }

# Barva přiřazená každé sekci menu — používá se pro nadpis i položky v hlavním menu
SEC_CURRENCY="$C_GREEN"
SEC_DINOS="$C_CYAN"
SEC_UNLOCKS="$C_YELLOW"
SEC_LEVELS="$C_ORANGE"
SEC_ARENA="$C_RED"
SEC_VEHICLES="$C_BLUE"
SEC_SEARCH="$C_MAGENTA"
SEC_BACKUP="$C_WHITE"

header() { echo -e "${1}${C_BOLD}== $2 ==${C_RESET}"; }

# --- Kontrola python3 ----------------------------------------------------
#if ! command -v python3 >/dev/null 2>&1; then
#    err "python3 nenalezen. Na Termuxu nainstaluj: pkg install python"
#    exit 1
#fi

# --- Automatická detekce souboru se savem --------------------------------
# Pořadí priorit: 1) argument skriptu  2) standardní cesta balíčku na zařízení
#                 3) hledání v aktuálním adresáři (pro případ práce s kopií souboru)
XML_PATH="${1:-}"

if [ -z "$XML_PATH" ] && [ -f "$DEFAULT_PATH" ]; then
    XML_PATH="$DEFAULT_PATH"
    info "Nalezena standardní cesta balíčku: $XML_PATH"
fi

if [ -z "$XML_PATH" ]; then
    FOUND=$(find . -maxdepth 3 -iname "$SAVE_FILENAME" 2>/dev/null | head -n1)
    if [ -n "$FOUND" ]; then
        XML_PATH="$FOUND"
        info "Nalezen save v aktuálním adresáři: $XML_PATH"
    fi
fi

if [ -z "$XML_PATH" ] || [ ! -f "$XML_PATH" ]; then
    err "Save soubor nenalezen (ani na $DEFAULT_PATH, ani v okolí)."
    err "Spusť skript s cestou jako argumentem:"
    err "  ./dino_save_editor.sh /data/data/pl.idreams.Dino/shared_prefs/pl.idreams.Dino.v2.playerprefs.xml"
    exit 1
fi

# --- Automatické ukončení hry před editací -------------------------------
# Zabrání tomu, aby živý proces hry při svém vlastním ukládání přepsal
# změny, které tady provedeme na disku.
stop_game() {
    if command -v am >/dev/null 2>&1; then
        if am force-stop "$PKG" >/dev/null 2>&1; then
            ok "Hra ($PKG) ukončena (am force-stop)."
        else
            warn "Nepodařilo se zavolat 'am force-stop' (chybí root/su?). Zkontroluj ručně, že hra neběží."
        fi
    else
        warn "Příkaz 'am' není dostupný v PATH — hru prosím zavři ručně, ať neběží na pozadí."
    fi
}
stop_game

WORKDIR=$(mktemp -d)
WORK_JSON="$WORKDIR/save.json"
ENGINE="$WORKDIR/engine.py"
DIRTY=0

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

info "Save soubor: $XML_PATH"
info "Pracovní adresář: $WORKDIR"

# ============================================================================
#  PYTHON ENGINE — veškerá práce s base64/urlencode/JSON blobem
# ============================================================================
cat > "$ENGINE" << 'PYEOF'
import sys, re, json, base64, urllib.parse

def read_xml(path):
    with open(path, encoding='utf-8') as f:
        return f.read()

def find_string_field(xml, name):
    m = re.search(r'<string name="%s">(.*?)</string>' % re.escape(name), xml)
    if not m:
        raise SystemExit(f"Pole '{name}' nenalezeno v XML.")
    return m, m.group(1)

def decode_blob(raw):
    b64 = urllib.parse.unquote(raw)
    padded = b64 + '=' * (-len(b64) % 4)
    return json.loads(base64.b64decode(padded))

def encode_blob(data):
    j = json.dumps(data, separators=(', ', ': '))
    b64 = base64.b64encode(j.encode('utf-8')).decode('ascii')
    return urllib.parse.quote(b64, safe='')

def cmd_decode(xml_path, json_out):
    xml = read_xml(xml_path)
    _, raw = find_string_field(xml, 'save')
    data = decode_blob(raw)
    with open(json_out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False)
    print("OK")

def cmd_encode(xml_path, json_in, xml_out):
    xml = read_xml(xml_path)
    m, _ = find_string_field(xml, 'save')
    with open(json_in, encoding='utf-8') as f:
        data = json.load(f)
    new_encoded = encode_blob(data)
    new_xml = xml[:m.start(1)] + new_encoded + xml[m.end(1):]
    with open(xml_out, 'w', encoding='utf-8') as f:
        f.write(new_xml)
    print("OK")

def load(json_path):
    with open(json_path, encoding='utf-8') as f:
        return json.load(f)

def dump(json_path, data):
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False)

def cmd_summary(json_path):
    d = load(json_path)
    print(f"Hráč:              {d.get('_PlayerName')}")
    print(f"Mince:             {d.get('_CoinsNo')}")
    print(f"Bankovky:          {d.get('_BillsNo')}")
    print(f"Prasátko:          {d.get('_PiggyBank')}")
    print(f"Kameny:            {d.get('_StonesNo')}")
    print(f"Lajky:             {d.get('_LikesNo')}")
    print(f"XP:                {d.get('_XPNum')}")
    print(f"Level banky:       {d.get('_BankLevel')}")
    print(f"Level pokladny:    {d.get('_TicketBoothLevel')}")
    print(f"Vejce (inkubátor): {d.get('_IncubatedEggsNo')}")
    print(f"Arena rank:        {d.get('_ArenaPlayerRank')}")
    print(f"Arena rating:      {d.get('_ArenaMultiplayerRating')}")
    cages = d.get('_Cages', {})
    total = sum(len(c.get('_Dinos', [])) for c in cages.values())
    print(f"Počet klecí:       {len(cages)}  (celkem dinosaurů: {total})")

def cmd_set_currency(json_path, field, value):
    d = load(json_path)
    if field not in d:
        print(f"CHYBA: pole '{field}' v save neexistuje.")
        return
    old = d[field]
    d[field] = int(value)
    dump(json_path, d)
    print(f"OK  {field}: {old} -> {d[field]}")

CURRENCY_FIELDS = [
    "_CoinsNo", "_BillsNo", "_PiggyBank", "_PiggyBankCollectedCoins",
    "_StonesNo", "_LikesNo", "_XPNum", "_IncubatedEggsNo",
]

def cmd_list_dinos(json_path):
    d = load(json_path)
    cages = d.get('_Cages', {})

    # ANSI colors
    RESET = "\033[0m"
    DIM = "\033[2m"
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    MAGENTA = "\033[35m"
    WHITE = "\033[97m"
    RED = "\033[31m"

    print(
        f"{DIM}"
        f"{'IDX':<5}"
        f"{'CAGE':<15}"
        f"{'DINO ID':<18}"
        f"{'LEVEL':<8}"
        f"{'TYPE':<14}"
        f"{'GUID'}"
        f"{RESET}"
    )

    print(f"{DIM}{'-'*80}{RESET}")

    i = 0

    for cage_id, cage in cages.items():
        for dino in cage.get('_Dinos', []):

            dino_id = str(dino.get('_ID', 'UNKNOWN'))
            level = int(dino.get('_Level', 0))
            guid = str(dino.get('_GUID', ''))

            # Speciální dinosaurus
            if dino.get('_Special'):
                dtype = f"{MAGENTA}UNICORN{RESET}"
            else:
                dtype = f"{WHITE}NORMAL{RESET}"

            # Barva levelu
            if level >= 6:
                level_color = GREEN
            elif level >= 4:
                level_color = YELLOW
            else:
                level_color = RED

            print(
                f"{DIM}{i:<5}{RESET}"
                f"{CYAN}{cage_id:<15}{RESET}"
                f"{GREEN}{dino_id:<18}{RESET}"
                f"{level_color}{level:<8}{RESET}"
                f"{dtype:<14}"
                f"{DIM}{guid}{RESET}"
            )

            i += 1
            
def _iter_dinos(d):
    out = []
    for cage_id, cage in d.get('_Cages', {}).items():
        for dino in cage.get('_Dinos', []):
            out.append((cage_id, cage, dino))
    return out

def cmd_dino_set_level(json_path, index, level):
    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("CHYBA: neplatný index dinosaura.")
        return
    level = int(level)
    if level > 6:
        print("VAROVÁNÍ: level > 6 může přesáhnout interní grafickou tabulku hry "
              "(ověřeno pádem při level=15, tabulka má jen 6 položek). "
              "Přesto nastavuji, ale hra se může zaseknout při načítání.")
    _, _, dino = dinos[idx]
    old = dino['_Level']
    dino['_Level'] = level
    dump(json_path, d)
    print(f"OK  dino[{idx}] level: {old} -> {level}")

def cmd_dino_set_special(json_path, index, value):
    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("CHYBA: neplatný index dinosaura.")
        return
    _, _, dino = dinos[idx]
    dino['_Special'] = (value == '1')
    dump(json_path, d)
    print(f"OK  dino[{idx}] _Special = {dino['_Special']}")

def cmd_dino_set_all_special(json_path, value):
    d = load(json_path)
    n = 0
    for _, _, dino in _iter_dinos(d):
        dino['_Special'] = (value == '1')
        n += 1
    dump(json_path, d)
    print(f"OK  nastaveno _Special={value=='1'} u {n} dinosaurů")

def cmd_dino_set_all_level(json_path, level):
    level = int(level)
    d = load(json_path)
    n = 0
    for _, _, dino in _iter_dinos(d):
        dino['_Level'] = level
        n += 1
    dump(json_path, d)
    if level > 6:
        print("VAROVÁNÍ: level > 6 riskuje pád při načítání (viz dino_set_level).")
    print(f"OK  nastaveno level={level} u {n} dinosaurů")

def cmd_dino_preview(json_path, index):
    """Pravý panel: detailní statistiky vybraného dinosaura."""
    RESET = "\033[0m"; BOLD = "\033[1m"; CYAN = "\033[36m"; GREEN = "\033[32m"
    YELLOW = "\033[33m"; MAGENTA = "\033[35m"; DIM = "\033[2m"

    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("Neplatný index dinosaura.")
        return
    cage_id, cage, dino = dinos[idx]

    level = dino.get('_Level', 0)
    special = dino.get('_Special', False)
    level_color = GREEN if level >= 6 else (YELLOW if level >= 4 else "\033[31m")

    print(f"{BOLD}{CYAN}=== {dino.get('_ID')} (#{idx}) ==={RESET}")
    print()
    print(f"{DIM}Klec:{RESET}          {cage_id}")
    print(f"{DIM}GUID:{RESET}          {dino.get('_GUID')}")
    print()
    print(f"{DIM}Level:{RESET}         {level_color}{level}{RESET}  {DIM}(bezpečné max 6){RESET}")
    print(f"{DIM}Unicorn:{RESET}       {(MAGENTA + 'ANO (barevný)' + RESET) if special else 'ne'}")
    print()
    print(f"{DIM}Boost Power:{RESET}   {dino.get('_BoostPower', 0)}")
    print(f"{DIM}Boost HP:{RESET}      {dino.get('_BoostHP', 0)}")
    print(f"{DIM}Boost Speed:{RESET}   {dino.get('_BoostSpeed', 0)}")
    print(f"{DIM}Boost Defense:{RESET} {dino.get('_BoostDefense', 0)}")
    print()
    print(f"{DIM}Poprvé viděn:{RESET}  {dino.get('_FirstTime')}")
    print(f"{DIM}Arena reborn:{RESET}  {dino.get('_ArenaRebornTime')}")
    print()
    print(f"{DIM}--- klec celkem ---{RESET}")
    print(f"{DIM}Celkem dinů v kleci:{RESET} {cage.get('_TotalDinosNo')}")
    print(f"{DIM}Golds:{RESET}               {cage.get('_GoldsNo')}")

DINO_FIELD_LABELS = [
    ("level",         "Level"),
    ("special",       "Unicorn (barevný)"),
    ("boostpower",    "Boost Power"),
    ("boosthp",       "Boost HP"),
    ("boostspeed",    "Boost Speed"),
    ("boostdefense",  "Boost Defense"),
]

def cmd_dino_fields(json_path, index):
    """Levý panel druhé úrovně: seznam upravitelných polí vybraného dina."""
    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("neplatny|Neplatný index dinosaura")
        return
    _, _, dino = dinos[idx]
    values = {
        "level": dino.get('_Level', 0),
        "special": "ano" if dino.get('_Special') else "ne",
        "boostpower": dino.get('_BoostPower', 0),
        "boosthp": dino.get('_BoostHP', 0),
        "boostspeed": dino.get('_BoostSpeed', 0),
        "boostdefense": dino.get('_BoostDefense', 0),
    }
    for key, label in DINO_FIELD_LABELS:
        print(f"{key}|{label} = {values[key]}")

def cmd_dino_set_field(json_path, index, field_key, value):
    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("CHYBA: neplatný index dinosaura.")
        return
    _, _, dino = dinos[idx]
    if field_key == "level":
        lvl = int(value)
        if lvl > 6:
            print("VAROVÁNÍ: level > 6 může přesáhnout interní grafickou tabulku hry "
                  "(ověřeno pádem, tabulka má jen 6 položek).")
        dino['_Level'] = lvl
    elif field_key == "special":
        dino['_Special'] = value.strip().lower() in ("1", "a", "ano", "true", "y", "yes")
    elif field_key == "boostpower":
        dino['_BoostPower'] = int(value)
    elif field_key == "boosthp":
        dino['_BoostHP'] = int(value)
    elif field_key == "boostspeed":
        dino['_BoostSpeed'] = int(value)
    elif field_key == "boostdefense":
        dino['_BoostDefense'] = int(value)
    else:
        print(f"CHYBA: neznámé pole '{field_key}'")
        return
    dump(json_path, d)
    print(f"OK  {field_key} nastaveno")

def cmd_dino_fzf_lines(json_path):
    """Řádky pro fzf výběr dinosaura: 'idx|zbytek na zobrazení' (delimiter '|')."""
    d = load(json_path)
    for i, (cage_id, cage, dino) in enumerate(_iter_dinos(d)):
        dtype = "UNICORN" if dino.get('_Special') else "normal"
        print(f"{i}|{cage_id:<12} {str(dino.get('_ID', '')):<10} "
              f"lvl={dino.get('_Level', 0):<3} {dtype:<8} {dino.get('_GUID', '')}")

def cmd_dino_set_boost(json_path, index, power, hp, speed, defense):
    d = load(json_path)
    dinos = _iter_dinos(d)
    idx = int(index)
    if idx < 0 or idx >= len(dinos):
        print("CHYBA: neplatný index dinosaura.")
        return
    _, _, dino = dinos[idx]
    dino['_BoostPower'] = int(power)
    dino['_BoostHP'] = int(hp)
    dino['_BoostSpeed'] = int(speed)
    dino['_BoostDefense'] = int(defense)
    dump(json_path, d)
    print(f"OK  dino[{idx}] boosty nastaveny")

def cmd_fill_bones(json_path):
    d = load(json_path)
    n = 0
    for dino_id, chest in d.get('_Chests', {}).items():
        idx = chest.get('_ReconstructionBonesIndex', {})
        bones = chest.setdefault('_Bones', {})
        for bone_name, needed in idx.items():
            bones[bone_name] = max(needed, bones.get(bone_name, 0), 999)
            n += 1
    dump(json_path, d)
    print(f"OK  doplněno {n} typů kostí ve všech schránkách na max")

UNLOCK_FIELDS = [
    "_TopPanelUnlocked", "_ExpeditionUnlocked", "_IncubatorUnlocked",
    "_TrashBestiaryUnlocked", "_MultiDigUnlocked", "_MultiDigSpecialUnlocked",
    "_ArenaTournamentUnlocked", "_DressRoomUnlocked", "_ArenaUnlocked",
    "_ArenaMultiplayerUnlocked", "_PhotoBoothUnlocked", "_UndegroundUnlocked",
    "_FactoryUnlocked", "_ArenaTrainingCampUnlocked", "_FbLiked",
    "_BestiaryVisited", "HasAnyTotem",
]

def cmd_list_unlocks(json_path):
    d = load(json_path)
    for i, field in enumerate(UNLOCK_FIELDS):
        val = d.get(field)
        mark = "ANO" if val else "ne "
        print(f"{i:2d} | [{mark}] {field}")

def cmd_toggle_unlock(json_path, index):
    d = load(json_path)
    idx = int(index)
    if idx < 0 or idx >= len(UNLOCK_FIELDS):
        print("CHYBA: neplatný index.")
        return
    field = UNLOCK_FIELDS[idx]
    d[field] = not d.get(field, False)
    dump(json_path, d)
    print(f"OK  {field} -> {d[field]}")

def cmd_set_arena(json_path, rank, rating, wins_t, wins_m, lost_m, lost_strike):
    d = load(json_path)
    d['_ArenaPlayerRank'] = int(rank)
    d['_ArenaMultiplayerRating'] = int(rating)
    d['ArenaMultiplayerRating'] = int(rating)
    d['_NumTournamentWins'] = int(wins_t)
    d['NumTournamentWins'] = int(wins_t)
    d['_NumMultiplayerWins'] = int(wins_m)
    d['_NumMultiplayerLost'] = int(lost_m)
    d['_ArenaMultiplayerLostStrike'] = int(lost_strike)
    dump(json_path, d)
    print("OK  arena stats nastaveny")

def cmd_set_levels_safe(json_path, bank_level, ticket_level):
    d = load(json_path)
    bank_level = int(bank_level)
    ticket_level = int(ticket_level)
    d['_BankLevel'] = bank_level
    d['_TicketBoothLevel'] = ticket_level
    dump(json_path, d)
    if bank_level > 6 or ticket_level > 4:
        print("VAROVÁNÍ: hodnoty nad ověřené bezpečné maximum (bank<=6, "
              "pokladna<=4) mohou způsobit pád/zaseknutí načítání (index mimo tabulku).")
    print(f"OK  _BankLevel={bank_level}  _TicketBoothLevel={ticket_level}")

# ---------------------------------------------------------------------
# VOZIDLA / DYNAMIT
# _VehiclesAbilityCounter._Items.<VehicleID>  = počet "dynamitu"/nábojů schopnosti
# _VehiclesBuyCounter._Items.<VehicleID>      = kolikrát bylo vozidlo koupeno/vylepšeno
# Obě jsou "Counter" struktury s odvozenými poli Count/SumAll/_MaxSumAll,
# která si po úpravě přepočítáme, ať zůstanou vnitřně konzistentní.
# ---------------------------------------------------------------------

def _recompute_counter(counter):
    items = counter.get('_Items', {})
    counter['Count'] = len(items)
    total = sum(v for v in items.values() if isinstance(v, (int, float)))
    counter['SumAll'] = total
    counter['_MaxSumAll'] = max(counter.get('_MaxSumAll', 0), total)

def cmd_list_vehicles(json_path):
    d = load(json_path)
    ability = d.get('_VehiclesAbilityCounter', {}).get('_Items', {})
    buy = d.get('_VehiclesBuyCounter', {}).get('_Items', {})
    vehicles = d.get('_Vehicles', []) or list(set(ability) | set(buy))
    selected = d.get('_SelectedVehicleID')
    for v in sorted(vehicles):
        mark = " (vybráno)" if v == selected else ""
        print(f"{v}{mark}: dynamit/ability={ability.get(v, 0)}   koupeno={buy.get(v, 0)}x")

def cmd_set_vehicle_ability(json_path, vehicle_id, value):
    d = load(json_path)
    counter = d.setdefault('_VehiclesAbilityCounter',
                            {'_Items': {}, '_MaxSumAll': 0, 'Count': 0, 'SumAll': 0})
    items = counter.setdefault('_Items', {})
    old = items.get(vehicle_id, 0)
    items[vehicle_id] = int(value)
    _recompute_counter(counter)
    if vehicle_id not in d.get('_Vehicles', []):
        d.setdefault('_Vehicles', []).append(vehicle_id)
    dump(json_path, d)
    print(f"OK  dynamit/ability u {vehicle_id}: {old} -> {value}")

def cmd_set_vehicle_buy(json_path, vehicle_id, value):
    d = load(json_path)
    counter = d.setdefault('_VehiclesBuyCounter',
                            {'_Items': {}, '_MaxSumAll': 0, 'Count': 0, 'SumAll': 0})
    items = counter.setdefault('_Items', {})
    old = items.get(vehicle_id, 0)
    items[vehicle_id] = int(value)
    _recompute_counter(counter)
    dump(json_path, d)
    print(f"OK  počet koupí u {vehicle_id}: {old} -> {value}")

# ---------------------------------------------------------------------
# OBECNÉ HLEDÁNÍ A ÚPRAVA LIBOVOLNÉHO POLE (podle cesty klíčů)
# Užitečné pro cokoliv, co ještě není v savu vidět / co teprve přibude
# (např. budoucí "mechanické dinosaury") — najdeš přesnou cestu hledáním
# a pak ji rovnou upravíš.
# ---------------------------------------------------------------------

def _walk(obj, prefix, term, results, limit=200):
    if len(results) >= limit:
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else k
            if term in k.lower():
                results.append((path, v if not isinstance(v, (dict, list)) else f"<{type(v).__name__}, {len(v)} položek>"))
            _walk(v, path, term, results, limit)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            path = f"{prefix}.{i}"
            _walk(v, path, term, results, limit)

def cmd_search(json_path, term):
    d = load(json_path)
    results = []
    _walk(d, "", term.lower(), results)
    if not results:
        print(f"Nic nenalezeno pro '{term}'.")
        return
    for path, val in results:
        print(f"{path} = {val}")

def _parse_value(v):
    if v == 'true':
        return True
    if v == 'false':
        return False
    if v == 'null':
        return None
    try:
        if '.' in v:
            return float(v)
        return int(v)
    except ValueError:
        return v

def _navigate(cur, parts, create=False):
    for p in parts:
        if isinstance(cur, list):
            cur = cur[int(p)]
        elif isinstance(cur, dict):
            if create and p not in cur:
                cur[p] = {}
            cur = cur[p]
        else:
            raise KeyError(f"nelze sestoupit do '{p}' (rodič není dict/list)")
    return cur

def cmd_get_path(json_path, path):
    d = load(json_path)
    parts = path.split('.')
    try:
        val = _navigate(d, parts)
    except (KeyError, IndexError, ValueError) as e:
        print(f"CHYBA: cesta '{path}' neexistuje ({e})")
        return
    print(f"{path} = {val}")

def cmd_set_path(json_path, path, value):
    d = load(json_path)
    parts = path.split('.')
    try:
        parent = _navigate(d, parts[:-1])
        last = parts[-1]
        old = None
        if isinstance(parent, list):
            idx = int(last)
            old = parent[idx]
            parent[idx] = _parse_value(value)
        elif isinstance(parent, dict):
            old = parent.get(last)
            parent[last] = _parse_value(value)
        else:
            raise KeyError("rodič není dict/list")
    except (KeyError, IndexError, ValueError) as e:
        print(f"CHYBA: cesta '{path}' se nepodařilo nastavit ({e})")
        return
    dump(json_path, d)
    print(f"OK  {path}: {old} -> {_parse_value(value)}")

if __name__ == '__main__':
    cmd = sys.argv[1]
    args = sys.argv[2:]
    try:
        globals()[f"cmd_{cmd}"](*args)
    except BrokenPipeError:
        # preview panel ve fzf může výstup uříznout (scroll/resize) — nejde o chybu
        try:
            sys.stdout.close()
        except Exception:
            pass
PYEOF

run_engine() {
    /data/data/com.termux/files/usr/bin/python3.14 "$ENGINE" "$@"
}

# --- Dekódování savu do pracovního JSONu ---------------------------------
info "Dekóduji save..."
if ! run_engine decode "$XML_PATH" "$WORK_JSON"; then
    err "Dekódování selhalo. Je to opravdu platný pl.idreams.Dino playerprefs.xml?"
    exit 1
fi
ok "Save dekódován do paměti."

# --- Automatická záloha při KAŽDÉ jednotlivé úpravě ----------------------
# Zálohy jdou do skryté složky vedle save souboru, ať přežijí i restart
# skriptu (pracovní JSON v /tmp se maže při ukončení). Drží se posledních
# 50 kroků, starší se automaticky mažou.
BACKUP_DIR="$(dirname "$XML_PATH")/.dino_save_backups"
mkdir -p "$BACKUP_DIR" 2>/dev/null

auto_backup() {
    local ts n
    ts=$(date +%Y%m%d_%H%M%S)
    n=$(printf '%03d' $((RANDOM % 1000)))
    cp "$WORK_JSON" "$BACKUP_DIR/edit_${ts}_${n}.json" 2>/dev/null
    # rotace: nech jen posledních 50 záloh
    ls -1t "$BACKUP_DIR"/edit_*.json 2>/dev/null | tail -n +51 | xargs -r rm -f
}

mark_dirty() {
    DIRTY=1
    auto_backup
}

backup_original() {
    local bak="${XML_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$XML_PATH" "$bak"
    ok "Záloha originálu: $bak"
}

launch_game() {
    if command -v am >/dev/null 2>&1; then
        if am start -n "$LAUNCH_ACTIVITY" >/dev/null 2>&1; then
            ok "Hra spuštěna."
        else
            warn "Nepodařilo se hru spustit přes 'am start' (chybí root/su?)."
        fi
    else
        warn "Příkaz 'am' není dostupný — spusť hru ručně."
    fi
}

save_to_disk() {
    # Pojistka: hra nesmí běžet, jinak by při vlastním ukládání/ukončení
    # mohla přepsat to, co teď zapíšeme na disk.
    stop_game
    backup_original
    if run_engine encode "$XML_PATH" "$WORK_JSON" "$XML_PATH"; then
        ok "Uloženo do: $XML_PATH"
        DIRTY=0
        read -rp "Spustit hru znovu? (a/n): " r
        [ "$r" = "a" ] && launch_game
    else
        err "Uložení selhalo."
    fi
}

pause() { read -rp $'\nEnter pro pokračování...' _; }

menu_currency() {
    while true; do
        clear
        header "$SEC_CURRENCY" "MĚNA A ZDROJE"
        for i in "${!CURR_LIST[@]}"; do
            echo -e "${SEC_CURRENCY}$i)${C_RESET} ${CURR_LIST[$i]}"
        done
        echo "b) Zpět"
        read -rp "Volba: " c
        [ "$c" = "b" ] && return
        if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -lt "${#CURR_LIST[@]}" ]; then
            field="${CURR_LIST[$c]}"
            read -rp "Nová hodnota pro $field: " val
            run_engine set_currency "$WORK_JSON" "$field" "$val"
            mark_dirty
            pause
        fi
    done
}
CURR_LIST=(_CoinsNo _BillsNo _PiggyBank _PiggyBankCollectedCoins _StonesNo _LikesNo _XPNum _IncubatedEggsNo)

select_dino_fzf() {
    # Levý panel: seznam dinosaurů (šipky nahoru/dolů). Pravý panel: živý
    # náhled statistik aktuálně podsvíceného dina (aktualizuje se za pohybu).
    # Enter = vybrat pro editaci, Esc = zpět (prázdný výstup).
    local py="/data/data/com.termux/files/usr/bin/python3.14"
    local fzfbin="/data/data/com.termux/files/usr/bin/fzf"

    {
        echo "BULK|>>> HROMADNÉ AKCE (level/unicorn u všech, doplnit kosti) <<<"
        run_engine dino_fzf_lines "$WORK_JSON"
    } | "$fzfbin" \
        --ansi --border --height=80% --layout=reverse \
        --delimiter='|' --with-nth=2.. \
        --preview="[ {1} = BULK ] && echo 'Hromadné akce nad všemi dinosaury.' || \"$py\" \"$ENGINE\" dino_preview \"$WORK_JSON\" {1}" \
        --preview-window=right:55%:wrap \
        --header='↑/↓ vyber dinosaura • Enter = upravit • Esc = zpět' \
        --prompt="Dinosaurus > " \
    | cut -d'|' -f1
}

edit_dino_fzf() {
    # Druhá úroveň: seznam upravitelných polí zvoleného dina vlevo,
    # napravo pořád stejný živý přehled celého dina pro kontext.
    local idx="$1"
    local py="/data/data/com.termux/files/usr/bin/python3.14"
    local fzfbin="/data/data/com.termux/files/usr/bin/fzf"
    while true; do
        picked=$(run_engine dino_fields "$WORK_JSON" "$idx" | "$fzfbin" \
            --ansi --border --height=80% --layout=reverse \
            --delimiter='|' --with-nth=2.. \
            --preview="\"$py\" \"$ENGINE\" dino_preview \"$WORK_JSON\" $idx" \
            --preview-window=right:55%:wrap \
            --header='Enter = upravit pole • Esc = zpět na seznam dinosaurů' \
            --prompt="Pole > ")
        [ -z "$picked" ] && return
        key=$(echo "$picked" | cut -d'|' -f1)
        label=$(echo "$picked" | cut -d'|' -f2- | sed 's/ =.*//')
        if [ "$key" = "special" ]; then
            read -rp "Unicorn (barevný)? (a/n): " v
            val=$([ "$v" = "a" ] && echo 1 || echo 0)
        else
            read -rp "Nová hodnota pro $label: " val
        fi
        run_engine dino_set_field "$WORK_JSON" "$idx" "$key" "$val"
        mark_dirty
    done
}

bulk_dino_menu() {
    local fzfbin="/data/data/com.termux/files/usr/bin/fzf"
    local opts="setalllevel|Nastavit level VŠECH dinů (bezpečné max 6)
setallspecial|Nastavit unicorn (_Special) u VŠECH dinů
fillbones|Doplnit kosti na max ve všech schránkách (okamžitá rekonstrukce)"
    picked=$(printf '%s\n' "$opts" | "$fzfbin" \
        --ansi --border --height=40% --layout=reverse \
        --delimiter='|' --with-nth=2.. \
        --header='Hromadné akce • Esc = zpět' --prompt="Akce > ")
    [ -z "$picked" ] && return
    key=$(echo "$picked" | cut -d'|' -f1)
    case "$key" in
        setalllevel)
            read -rp "Level pro všechny (bezpečné max = 6): " lvl
            run_engine dino_set_all_level "$WORK_JSON" "$lvl"
            mark_dirty; pause ;;
        setallspecial)
            read -rp "Unicorn pro všechny? (1=ano/0=ne): " v
            run_engine dino_set_all_special "$WORK_JSON" "$v"
            mark_dirty; pause ;;
        fillbones)
            run_engine fill_bones "$WORK_JSON"
            mark_dirty; pause ;;
    esac
}

menu_dinos() {
    while true; do
        clear
        header "$SEC_DINOS" "DINOSAUŘI"
        sel=$(select_dino_fzf)
        [ -z "$sel" ] && return
        if [ "$sel" = "BULK" ]; then
            bulk_dino_menu
        else
            edit_dino_fzf "$sel"
        fi
    done
}

menu_unlocks() {
    while true; do
        clear
        header "$SEC_UNLOCKS" "ODEMČENÉ FUNKCE"
        run_engine list_unlocks "$WORK_JSON"
        echo
        echo "Zadej číslo pro přepnutí ON/OFF, nebo 'b' pro zpět."
        read -rp "Volba: " c
        [ "$c" = "b" ] && return
        if [[ "$c" =~ ^[0-9]+$ ]]; then
            run_engine toggle_unlock "$WORK_JSON" "$c"
            mark_dirty; pause
        fi
    done
}

menu_levels() {
    clear
    header "$SEC_LEVELS" "ÚROVNĚ BANKY / POKLADNY"
    warn "Tyto hodnoty indexují do pevných tabulek v binárce hry."
    warn "Ověřené bezpečné maximum: banka <= 6, pokladna <= 4."
    warn "Vyšší hodnoty = riziko zaseknutí při načítání (86% bug)."
    read -rp "Level banky: " bl
    read -rp "Level pokladny: " tl
    run_engine set_levels_safe "$WORK_JSON" "$bl" "$tl"
    mark_dirty; pause
}

menu_arena() {
    clear
    header "$SEC_ARENA" "ARÉNA"
    read -rp "Arena rank: " rank
    read -rp "Arena rating: " rating
    read -rp "Výhry v turnaji: " wt
    read -rp "Výhry v multiplayeru: " wm
    read -rp "Prohry v multiplayeru: " lm
    read -rp "Série proher (lost strike): " ls
    run_engine set_arena "$WORK_JSON" "$rank" "$rating" "$wt" "$wm" "$lm" "$ls"
    mark_dirty; pause
}

menu_vehicles() {
    while true; do
        clear
        header "$SEC_VEHICLES" "VOZIDLA / DYNAMIT"
        run_engine list_vehicles "$WORK_JSON"
        echo
        echo -e "${SEC_VEHICLES}1)${C_RESET} Nastavit dynamit/ability počítadlo vozidla"
        echo -e "${SEC_VEHICLES}2)${C_RESET} Nastavit počet koupí/vylepšení vozidla"
        echo "b) Zpět"
        read -rp "Volba: " c
        case "$c" in
            1)
                read -rp "ID vozidla (např. Vehicle1, Vehicle2): " vid
                read -rp "Nová hodnota dynamitu: " val
                run_engine set_vehicle_ability "$WORK_JSON" "$vid" "$val"
                mark_dirty; pause ;;
            2)
                read -rp "ID vozidla (např. Vehicle1, Vehicle2): " vid
                read -rp "Nový počet koupí: " val
                run_engine set_vehicle_buy "$WORK_JSON" "$vid" "$val"
                mark_dirty; pause ;;
            b|B) return ;;
        esac
    done
}

menu_search() {
    clear
    header "$SEC_SEARCH" "HLEDAT & UPRAVIT LIBOVOLNÉ POLE"
    echo "Zadej část názvu pole (např. 'dynam', 'mech', 'level') — prohledá se celý save."
    read -rp "Hledat: " term
    [ -z "$term" ] && return
    echo
    run_engine search "$WORK_JSON" "$term"
    echo
    read -rp "Cesta pole k úpravě (Enter = neupravovat): " path
    [ -z "$path" ] && { pause; return; }
    read -rp "Nová hodnota: " val
    run_engine set_path "$WORK_JSON" "$path" "$val"
    mark_dirty; pause
}

menu_restore() {
    clear
    header "$SEC_BACKUP" "OBNOVIT ZE ZÁLOHY"
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/edit_*.json 2>/dev/null)
    if [ ${#backups[@]} -eq 0 ]; then
        warn "Žádné automatické zálohy zatím neexistují (vznikají při každé úpravě)."
        pause
        return
    fi
    for i in "${!backups[@]}"; do
        echo -e "${SEC_BACKUP}$i)${C_RESET} $(basename "${backups[$i]}")"
    done
    echo "b) Zpět"
    read -rp "Vyber zálohu k načtení: " c
    [ "$c" = "b" ] && return
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -lt "${#backups[@]}" ]; then
        cp "${backups[$c]}" "$WORK_JSON"
        mark_dirty
        ok "Načteno ze zálohy: $(basename "${backups[$c]}")"
        pause
    fi
}

show_status() {
    local json="$WORK_JSON"

    local player coins bills piggy stones likes xp bank ticket eggs cages dinos arena rating

    # Get values from python engine
    player=$(run_engine get_path "$json" "_PlayerName" 2>/dev/null | cut -d'=' -f2- | xargs)
    coins=$(run_engine get_path "$json" "_CoinsNo" 2>/dev/null | cut -d'=' -f2- | xargs)
    bills=$(run_engine get_path "$json" "_BillsNo" 2>/dev/null | cut -d'=' -f2- | xargs)
    piggy=$(run_engine get_path "$json" "_PiggyBank" 2>/dev/null | cut -d'=' -f2- | xargs)
    stones=$(run_engine get_path "$json" "_StonesNo" 2>/dev/null | cut -d'=' -f2- | xargs)
    likes=$(run_engine get_path "$json" "_LikesNo" 2>/dev/null | cut -d'=' -f2- | xargs)
    xp=$(run_engine get_path "$json" "_XPNum" 2>/dev/null | cut -d'=' -f2- | xargs)
    bank=$(run_engine get_path "$json" "_BankLevel" 2>/dev/null | cut -d'=' -f2- | xargs)
    ticket=$(run_engine get_path "$json" "_TicketBoothLevel" 2>/dev/null | cut -d'=' -f2- | xargs)
    eggs=$(run_engine get_path "$json" "_IncubatedEggsNo" 2>/dev/null | cut -d'=' -f2- | xargs)

    # Dino count
    dinos=$(/data/data/com.termux/files/usr/bin/python3.14 - "$json" <<'PY'
import json,sys
with open(sys.argv[1]) as f:
    d=json.load(f)
print(sum(len(c.get('_Dinos',[])) for c in d.get('_Cages',{}).values()))
PY
)

    cages=$(/data/data/com.termux/files/usr/bin/python3.14 - "$json" <<'PY'
import json,sys
with open(sys.argv[1]) as f:
    d=json.load(f)
print(len(d.get('_Cages',{})))
PY
)

    arena=$(run_engine get_path "$json" "_ArenaPlayerRank" 2>/dev/null | cut -d'=' -f2- | xargs)
    rating=$(run_engine get_path "$json" "_ArenaMultiplayerRating" 2>/dev/null | cut -d'=' -f2- | xargs)


    echo -e "${C_BOLD}╭────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_BOLD}│              🦖 DINO PARK SAVE EDITOR                     │${C_RESET}"
    echo -e "${C_BOLD}├────────────────────────────────────────────────────────────┤${C_RESET}"

    printf "${C_CYAN}│ %-12s${C_RESET} %-18s ${C_GREEN}%-12s${C_RESET} %-10s │\n" \
        "PLAYER:" "$player" "COINS:" "$coins"

    printf "${C_CYAN}│ %-12s${C_RESET} %-18s ${C_GREEN}%-12s${C_RESET} %-10s │\n" \
        "BILLS:" "$bills" "PIGGY:" "$piggy"

    printf "${C_CYAN}│ %-12s${C_RESET} %-18s ${C_GREEN}%-12s${C_RESET} %-10s │\n" \
        "STONES:" "$stones" "LIKES:" "$likes"

    printf "${C_YELLOW}│ %-12s${C_RESET} %-18s ${C_ORANGE}%-12s${C_RESET} %-10s │\n" \
        "XP:" "$xp" "EGGS:" "$eggs"

    echo -e "${C_BOLD}├────────────────────────────────────────────────────────────┤${C_RESET}"

    printf "${C_BLUE}│ %-12s${C_RESET} %-18s ${C_MAGENTA}%-12s${C_RESET} %-10s │\n" \
        "CAGES:" "$cages" "DINOS:" "$dinos"

    printf "${C_RED}│ %-12s${C_RESET} %-18s ${C_RED}%-12s${C_RESET} %-10s │\n" \
        "ARENA:" "$arena" "RATING:" "$rating"

    printf "${C_ORANGE}│ %-12s${C_RESET} %-18s ${C_ORANGE}%-12s${C_RESET} %-10s │\n" \
        "BANK:" "$bank" "TICKET:" "$ticket"

    echo -e "${C_BOLD}╰────────────────────────────────────────────────────────────╯${C_RESET}"

    if [ "$DIRTY" = "1" ]; then
        echo -e "${C_YELLOW}⚠ Neuložené změny${C_RESET}"
    fi
}

main_menu() {

    export FZF_DEFAULT_OPTS="
        --ansi
        --height=70%
        --layout=reverse
        --border=rounded
        --pointer='➤'
        --marker='✓'
        --prompt='Dino > '
        --info=inline
    "

    while true; do
        clear

        show_status

        echo

        MENU=$(cat <<EOF
${SEC_CURRENCY}💰 Měna a zdroje${C_RESET}
${SEC_DINOS}🦖 Dinosauři${C_RESET}
${SEC_UNLOCKS}🔓 Odemčené funkce${C_RESET}
${SEC_LEVELS}🏦 Úrovně banky / pokladny${C_RESET}
${SEC_ARENA}⚔ Aréna${C_RESET}
${SEC_VEHICLES}🚗 Vozidla / Dynamit${C_RESET}
${SEC_SEARCH}🔎 Hledat & upravit pole${C_RESET}
${SEC_BACKUP}💾 Obnovit ze zálohy${C_RESET}
${C_BOLD}💿 Uložit změny${C_RESET}
${C_RED}❌ Konec${C_RESET}
EOF
)

        choice=$(echo -e "$MENU" | /data/data/com.termux/files/usr/bin/fzf)

        # Cancel with ESC
        [ -z "$choice" ] && continue


        case "$choice" in

            *"💰"*)
                menu_currency
                ;;

            *"🦖"*)
                menu_dinos
                ;;

            *"🔓"*)
                menu_unlocks
                ;;

            *"🏦"*)
                menu_levels
                ;;

            *"⚔"*)
                menu_arena
                ;;

            *"🚗"*)
                menu_vehicles
                ;;

            *"🔎"*)
                menu_search
                ;;

            *"💾"*)
                menu_restore
                ;;

            *"💿"*)
                save_to_disk
                pause
                ;;

            *"❌"*)
                if [ "$DIRTY" = "1" ]; then
                    read -rp "Máš neuložené změny. Uložit před ukončením? (a/n): " a
                    [ "$a" = "a" ] && save_to_disk
                fi

                ok "Konec."
                exit 0
                ;;

        esac

    done
}
main_menu
