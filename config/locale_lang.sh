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

# Declare associative arrays for layout → Windows locale and keyboard code
declare -A LAYOUT_TO_WIN_LANG_KB=(
    [af]="ps-AF" [am]="am-ET" [ar]="ar-SA" [as]="as-IN" [az]="az-Latn-AZ"
    [ba]="ba-RU" [be]="be-BY" [bg]="bg-BG" [bn]="bn-IN" [bo]="bo-CN"
    [br]="br-FR" [bs]="bs-Latn-BA" [ca]="fr-CA" [cs]="cs-CZ" [cy]="cy-GB"
    [da]="da-DK" [de]="de-DE" [dv]="dv-MV" [el]="el-GR" [en]="en-US"
    [gb]="en-GB" [es]="es-ES" [et]="et-EE" [eu]="eu-ES" [fa]="fa-IR"
    [fi]="fi-FI" [fo]="fo-FO" [fr]="fr-FR" [ga]="ga-IE" [gd]="gd-GB"
    [gl]="gl-ES" [gu]="gu-IN" [he]="he-IL" [hi]="hi-IN" [hr]="hr-HR"
    [hu]="hu-HU" [hy]="hy-AM" [id]="id-ID" [is]="is-IS" [it]="it-IT"
    [iu]="iu-Latn-CA" [ja]="ja-JP" [ka]="ka-GE" [kk]="kk-KZ" [km]="km-KH"
    [kn]="kn-IN" [ko]="ko-KR" [kok]="kok-IN" [ky]="ky-KG" [lb]="lb-LU"
    [lo]="lo-LA" [lt]="lt-LT" [lv]="lv-LV" [mi]="mi-NZ" [mk]="mk-MK"
    [ml]="ml-IN" [mn]="mn-MN" [mr]="mr-IN" [ms]="ms-MY" [mt]="mt-MT"
    [nb]="nb-NO" [ne]="ne-NP" [nl]="nl-NL" [nn]="nn-NO" [or]="or-IN"
    [pa]="pa-IN" [pl]="pl-PL" [pt]="pt-PT" [ro]="ro-RO" [ru]="ru-RU"
    [si]="si-LK" [sk]="sk-SK" [sl]="sl-SI" [sq]="sq-AL" [sr]="sr-Cyrl-RS"
    [sv]="sv-SE" [sw]="sw-KE" [ta]="ta-IN" [te]="te-IN" [th]="th-TH"
    [tk]="tk-TM" [tr]="tr-TR" [tt]="tt-RU" [ug]="ug-CN" [uk]="uk-UA"
    [ur]="ur-PK" [uz]="uz-Latn-UZ" [vi]="vi-VN" [wo]="wo-SN" [yo]="yo-NG"
    [zh]="zh-CN"
)

declare -A LAYOUT_TO_WIN_KB_CODE=(
    [af]="0481" [am]="0455" [ar]="0401" [as]="044D" [az]="042C"
    [ba]="0468" [be]="0423" [bg]="0402" [bn]="0445" [bo]="0451"
    [br]="047e" [bs]="141A" [ca]="1009" [cs]="0405" [cy]="0452"
    [da]="0406" [de]="0407" [dv]="0465" [el]="0408" [en]="0409"
    [gb]="0809" [es]="0C0A" [et]="0425" [eu]="042D" [fa]="0429"
    [fi]="040B" [fo]="0438" [fr]="040C" [ga]="083C" [gd]="0491"
    [gl]="0456" [gu]="0447" [he]="040D" [hi]="0439" [hr]="041A"
    [hu]="040E" [hy]="042B" [id]="0421" [is]="040F" [it]="0410"
    [iu]="085D" [ja]="0411" [ka]="0437" [kk]="043F" [km]="0453"
    [kn]="044B" [ko]="0412" [kok]="0457" [ky]="0440" [lb]="046E"
    [lo]="0454" [lt]="0427" [lv]="0426" [mi]="0481" [mk]="042F"
    [ml]="044C" [mn]="0450" [mr]="044E" [ms]="043E" [mt]="043A"
    [nb]="0414" [ne]="0461" [nl]="0413" [nn]="0814" [or]="0448"
    [pa]="0446" [pl]="0415" [pt]="0816" [ro]="0418" [ru]="0419"
    [si]="045B" [sk]="041B" [sl]="0424" [sq]="041C" [sr]="0C1A"
    [sv]="041D" [sw]="0441" [ta]="0449" [te]="044A" [th]="041E"
    [tk]="0442" [tr]="041F" [tt]="0444" [ug]="0480" [uk]="0422"
    [ur]="0420" [uz]="0443" [vi]="042A" [wo]="0488" [yo]="046A"
    [zh]="0804"
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