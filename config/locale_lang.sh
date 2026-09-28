#!/bin/bash

# Locale.txt file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/linoffice.conf"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

cp -f "$CONFIG_FILE.default" "$CONFIG_FILE"
cp -f "$COMPOSE_FILE.default" "$COMPOSE_FILE"

# Detect Linux keyboard layout
function detect_keyboard_layout() {
    local layout_localectl=""
    local layout_x11=""
    local layout_kde=""
    local layout_gnome=""
    local layout_sway=""
    local layout_hyprland=""
    local layout=""

    # X11 detection
    if [[ "$XDG_SESSION_TYPE" == "x11" ]] && command -v setxkbmap &>/dev/null; then
        layout_x11=$(setxkbmap -query 2>/dev/null | awk '/layout:/ {print $2}')
    fi

    # localectl detection (Wayland or fallback)
    if command -v localectl &>/dev/null; then
        layout_localectl="$(localectl status 2>/dev/null | awk -F: '/X11 Layout/ {gsub(/^[ \t]+/, "", $2); print $2}' | cut -d',' -f1)"
    fi

    # KDE detection (Plasma 5 or 6)
    if [[ "$XDG_CURRENT_DESKTOP" == *KDE* || "$XDG_SESSION_DESKTOP" == *plasma* ]]; then
        if command -v qdbus6 &>/dev/null; then
            layout_kde="$(qdbus6 org.kde.keyboard /Layouts getLayout 2>/dev/null | tr ',' '\n' | head -n1)"
        elif command -v qdbus &>/dev/null; then
            layout_kde="$(qdbus org.kde.keyboard /Layouts getLayout 2>/dev/null | tr ',' '\n' | head -n1)"
        fi
    fi

    # GNOME
    if command -v gsettings &>/dev/null; then
        layout_gnome="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null | grep -oP "'xkb:\K[^']+" | cut -d'+' -f1 | head -n1)"
    fi

    # Sway
    if command -v swaymsg &>/dev/null; then
        if command -v jq &>/dev/null; then
            layout_sway="$(swaymsg -t get_inputs 2>/dev/null | jq -r '.[] | select(.type=="keyboard") | .xkb_active_layout_name' | head -n1 | cut -d'(' -f1 | xargs)"
        else
            layout_sway="$(swaymsg -t get_inputs 2>/dev/null | grep -o '"xkb_active_layout_name": "[^"]*"' | head -n1 | cut -d'"' -f4 | cut -d'(' -f1 | xargs)"
        fi
    fi

    # Hyprland
    if command -v hyprctl &>/dev/null; then
        layout_hyprland="$(hyprctl getoption input:kb_layout 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' | head -n1)"
        if [[ -z "$layout_hyprland" ]]; then
            layout_hyprland="$(hyprctl devices 2>/dev/null | grep -A 10 "Keyboard" | grep -o "keymap: [a-zA-Z_-]*" | head -n1 | cut -d' ' -f2)"
        fi
    fi

    # Combine all layouts in preferred order
    for l in "$layout_kde" "$layout_gnome" "$layout_sway" "$layout_hyprland" "$layout_x11" "$layout_localectl"; do
        if [[ -n "$l" && "$l" != "us" ]]; then
            layout="$l"
            break
        fi
    done

    # If all sources returned "us" or empty, fallback to known ones
    if [[ -z "$layout" ]]; then
        for l in "$layout_kde" "$layout_gnome" "$layout_sway" "$layout_hyprland" "$layout_x11" "$layout_localectl"; do
            if [[ -n "$l" ]]; then
                layout="$l"
                break
            fi
        done
    fi

    # Do not fallback to default value if everything fails
    echo "$layout"
}

# Run the function
layout=$(detect_keyboard_layout)

# Map the XKB layout name (as listed in xkeyboard-config's rules/base.lst) to
# the Windows input locale. The first array is used for KEYBOARD in compose.yaml,
# which dockur writes to the unattended install's InputLocale, so it accepts
# either a "LCID:KLID" pair or, for IME-based languages, a language tag that
# selects Windows' default IME. The second array is the keyboard layout ID
# (KLID) passed to FreeRDP with /kbd:layout.
# Values follow Microsoft's "Default input profiles (input locales) in Windows"
# for the matching language/region, except nl, fo and vn, where Windows ships a
# layout closer to the XKB one than its default (Dutch, Faeroese, Vietnamese).
# Layouts with no Windows counterpart are left out, so the defaults are kept.
declare -A LAYOUT_TO_WIN_LANG_KB=(
    [al]="041C:0000041C" [et]="am-ET" [am]="042B:0002042B" [ara]="0401:00000401"
    [eg]="0C01:00000401" [iq]="0801:00000401" [ma]="1801:00020401" [sy]="2801:00000401"
    [az]="042C:0000042C" [bd]="0845:00000445" [by]="0423:00000423" [be]="080C:0000080C"
    [dz]="085F:0000085F" [ba]="141A:0000041A" [bg]="0402:00030402" [mm]="0455:00130C00"
    [cn]="zh-CN" [hr]="041A:0000041A" [cz]="0405:00000405" [dk]="0406:00000406"
    [af]="048C:00050429" [mv]="0465:00000465" [nl]="0413:00000413" [bt]="0C51:00000C51"
    [au]="0C09:00000409" [nz]="1409:00001409" [za]="1C09:00000409" [gb]="0809:00000809"
    [ee]="0425:00000425" [fo]="0438:00000438" [ph]="0464:00000409" [fi]="040B:0000040B"
    [fr]="040C:0000040C" [ca]="0C0C:00001009" [cd]="240C:0000040C" [ge]="0437:00010437"
    [de]="0407:00000407" [at]="0C07:00000407" [ch]="0807:00000807" [gr]="0408:00000408"
    [il]="040D:0002040D" [hu]="040E:0000040E" [is]="040F:0000040F" [in]="0439:00010439"
    [id]="0421:00000409" [ie]="1809:00001809" [it]="0410:00000410" [jp]="ja-JP"
    [kz]="043F:0000043F" [kh]="0453:00000453" [kr]="ko-KR" [kg]="0440:00000440"
    [la]="0454:00000454" [lv]="0426:00020426" [lt]="0427:00010427" [mk]="042F:0001042F"
    [mt]="043A:0000043A" [md]="0818:00010418" [mn]="0450:00000450" [me]="2C1A:0000081A"
    [np]="0461:00000461" [no]="0414:00000414" [ir]="0429:00000429" [pl]="0415:00000415"
    [pt]="0816:00000816" [br]="0416:00000416" [ro]="0418:00010418" [ru]="0419:00000419"
    [rs]="281A:00000C1A" [lk]="045B:0000045B" [sk]="041B:0000041B" [si]="0424:00000424"
    [es]="0C0A:0000040A" [latam]="580A:0000080A" [ke]="0441:00000409" [se]="041D:0000041D"
    [tw]="zh-TW" [tj]="0428:00000428" [th]="041E:0000041E" [bw]="0832:00000432"
    [tm]="0442:00000442" [tr]="041F:0000041F" [ua]="0422:00020422" [pk]="0420:00000420"
    [uz]="0843:00000843" [vn]="042A:0000042A" [sn]="0488:00000488"
)

declare -A LAYOUT_TO_WIN_KB_CODE=(
    [al]="0000041C" [am]="0002042B" [ara]="00000401" [eg]="00000401"
    [iq]="00000401" [ma]="00020401" [sy]="00000401" [az]="0000042C"
    [bd]="00000445" [by]="00000423" [be]="0000080C" [dz]="0000085F"
    [ba]="0000041A" [bg]="00030402" [mm]="00130C00" [cn]="00000804"
    [hr]="0000041A" [cz]="00000405" [dk]="00000406" [af]="00050429"
    [mv]="00000465" [nl]="00000413" [bt]="00000C51" [au]="00000409"
    [nz]="00001409" [za]="00000409" [gb]="00000809" [ee]="00000425"
    [fo]="00000438" [ph]="00000409" [fi]="0000040B" [fr]="0000040C"
    [ca]="00001009" [cd]="0000040C" [ge]="00010437" [de]="00000407"
    [at]="00000407" [ch]="00000807" [gr]="00000408" [il]="0002040D"
    [hu]="0000040E" [is]="0000040F" [in]="00010439" [id]="00000409"
    [ie]="00001809" [it]="00000410" [jp]="00000411" [kz]="0000043F"
    [kh]="00000453" [kr]="00000412" [kg]="00000440" [la]="00000454"
    [lv]="00020426" [lt]="00010427" [mk]="0001042F" [mt]="0000043A"
    [md]="00010418" [mn]="00000450" [me]="0000081A" [np]="00000461"
    [no]="00000414" [ir]="00000429" [pl]="00000415" [pt]="00000816"
    [br]="00000416" [ro]="00010418" [ru]="00000419" [rs]="00000C1A"
    [lk]="0000045B" [sk]="0000041B" [si]="00000424" [es]="0000040A"
    [latam]="0000080A" [ke]="00000409" [se]="0000041D" [tw]="00000404"
    [tj]="00000428" [th]="0000041E" [bw]="00000432" [tm]="00000442"
    [tr]="0000041F" [ua]="00020422" [pk]="00000420" [uz]="00000843"
    [vn]="0000042A" [sn]="00000488"
)


# Function to detect system language
function get_system_language() {
    local lang_code
    if [[ -n "$LANG" ]]; then
        lang_code=$(echo "$LANG" | grep -oE '^[a-zA-Z]{2}')
        case "$lang_code" in
            ar) echo "Arabic" ;;
            bg) echo "Bulgarian" ;;
            zh) echo "Chinese" ;;
            hr) echo "Croatian" ;;
            cs) echo "Czech" ;;
            da) echo "Danish" ;;
            nl) echo "Dutch" ;;
            en) echo "English" ;;
            et) echo "Estonian" ;;
            fi) echo "Finnish" ;;
            fr) echo "French" ;;
            de) echo "German" ;;
            el) echo "Greek" ;;
            he) echo "Hebrew" ;;
            hu) echo "Hungarian" ;;
            it) echo "Italian" ;;
            ja) echo "Japanese" ;;
            ko) echo "Korean" ;;
            lv) echo "Latvian" ;;
            lt) echo "Lithuanian" ;;
            no) echo "Norwegian" ;;
            pl) echo "Polish" ;;
            pt) echo "Portuguese" ;;
            ro) echo "Romanian" ;;
            ru) echo "Russian" ;;
            sr) echo "Serbian" ;;
            sk) echo "Slovak" ;;
            sl) echo "Slovenian" ;;
            es) echo "Spanish" ;;
            sv) echo "Swedish" ;;
            th) echo "Thai" ;;
            tr) echo "Turkish" ;;
            uk) echo "Ukrainian" ;;
            *) echo "English" ;;  # Fallback
        esac
    else
        echo "English"  # Fallback if LANG not set
    fi
}


# Helper function to get Windows locale from language name
function get_windows_locale_from_language() {
    local lang=$1
    case "$lang" in
        "Arabic") echo "ar-SA" ;;
        "Bulgarian") echo "bg-BG" ;;
        "Chinese") echo "zh-CN" ;;
        "Croatian") echo "hr-HR" ;;
        "Czech") echo "cs-CZ" ;;
        "Danish") echo "da-DK" ;;
        "Dutch") echo "nl-NL" ;;
        "English") echo "en-001" ;; # English (World)
        "Estonian") echo "et-EE" ;;
        "Finnish") echo "fi-FI" ;;
        "French") echo "fr-FR" ;;
        "German") echo "de-DE" ;;
        "Greek") echo "el-GR" ;;
        "Hebrew") echo "he-IL" ;;
        "Hungarian") echo "hu-HU" ;;
        "Italian") echo "it-IT" ;;
        "Japanese") echo "ja-JP" ;;
        "Korean") echo "ko-KR" ;;
        "Latvian") echo "lv-LV" ;;
        "Lithuanian") echo "lt-LT" ;;
        "Norwegian") echo "no-NO" ;;
        "Polish") echo "pl-PL" ;;
        "Portuguese") echo "pt-PT" ;;
        "Romanian") echo "ro-RO" ;;
        "Russian") echo "ru-RU" ;;
        "Serbian") echo "sr-RS" ;;
        "Slovak") echo "sk-SK" ;;
        "Slovenian") echo "sl-SI" ;;
        "Spanish") echo "es-ES" ;;
        "Swedish") echo "sv-SE" ;;
        "Thai") echo "th-TH" ;;
        "Turkish") echo "tr-TR" ;;
        "Ukrainian") echo "uk-UA" ;;
        *) echo "en-001" ;; # set to English (World)
    esac
}

# Function to update compose.yaml
function update_compose_file() {
    local language=$1
    local region=$2
    local keyboard=$3

    # Check if compose.yaml exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo "Error: $COMPOSE_FILE does not exist."
        exit 1
    fi

    local updated=false

    # Update LANGUAGE line only if language was detected
    if [[ -n "$language" ]]; then
        if grep -q "LANGUAGE:" "$COMPOSE_FILE"; then
            sed -i "s/LANGUAGE:.*/LANGUAGE: \"$language\"/" "$COMPOSE_FILE"
            echo "Updated LANGUAGE: $language"
            updated=true
        else
            echo "Warning: LANGUAGE not found in compose file"
        fi
    else
        echo "Language detection failed - leaving LANGUAGE unchanged"
    fi

    # Update REGION line only if region was detected
    if [[ -n "$region" ]]; then
        if grep -q "REGION:" "$COMPOSE_FILE"; then
            sed -i "s/REGION:.*/REGION: \"$region\"/" "$COMPOSE_FILE"
            echo "Updated REGION: $region"
            updated=true
        else
            echo "Warning: REGION not found in compose file"
        fi
    else
        echo "Region detection failed - leaving REGION unchanged"
    fi

    # Update KEYBOARD line only if keyboard was detected
    if [[ -n "$keyboard" ]]; then
        if grep -q "KEYBOARD:" "$COMPOSE_FILE"; then
            sed -i "s/KEYBOARD:.*/KEYBOARD: \"$keyboard\"/" "$COMPOSE_FILE"
            echo "Updated KEYBOARD: $keyboard"
            updated=true
        else
            echo "Warning: KEYBOARD not found in compose file"
        fi
    else
        echo "Keyboard detection failed - leaving KEYBOARD unchanged"
    fi

    if [[ "$updated" == true ]]; then
        echo "Compose file has been updated successfully."
    else
        echo "No changes made to compose file."
    fi
}

# Function to update linoffice.conf
function update_config_file() {
    local kb_code=$1
    
    # Check if linoffice.conf exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: $CONFIG_FILE does not exist."
        exit 1
    fi
    
    # Update RDP_KBD line only if keyboard code was detected
    if [[ -n "$kb_code" ]]; then
        if grep -q "RDP_KBD=" "$CONFIG_FILE"; then
            sed -i "s/RDP_KBD=.*/RDP_KBD=\"\/kbd:layout:0x$kb_code\"/" "$CONFIG_FILE"
            echo "Updated RDP_KBD: /kbd:layout:0x$kb_code"
        else
            echo "Warning: RDP_KBD not found in config file"
        fi
    else
        echo "Keyboard code detection failed - leaving RDP_KBD unchanged"
    fi
}

# Get system language
SYSTEM_LANGUAGE=$(get_system_language)
REGION=$(get_windows_locale_from_language "$SYSTEM_LANGUAGE")
WIN_LANG_KB="${LAYOUT_TO_WIN_LANG_KB[$layout]}"
WIN_KB_CODE="${LAYOUT_TO_WIN_KB_CODE[$layout]}"

# Update compose.yaml
update_compose_file "$SYSTEM_LANGUAGE" "$REGION" "$WIN_LANG_KB"

# Update linoffice.conf
update_config_file "$WIN_KB_CODE"