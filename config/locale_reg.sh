#!/bin/bash

# Linux to Windows Regional Settings Converter
# Extracts specific locale settings from Linux and creates Windows .reg file

# Ensure output encoding is UTF-8 safe for processing
export LC_CTYPE=C.UTF-8
# Ensure iconv/grep/sed do not break on accents
export LANG="${LANG:-C.UTF-8}"

# Output files. Write into LINOFFICE_CONFIG_DIR, never into the read-only prefix.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LINOFFICE_CONFIG_DIR:-}" ]]; then
  # shellcheck source=../lib/paths.sh
  source "$SCRIPT_DIR/../lib/paths.sh"
fi
if [[ -n "${1:-}" ]]; then
  REG_FILE="$1"
else
  REG_FILE="${LINOFFICE_CONFIG_DIR}/oem/registry/regional_settings.reg"
fi
TEMP_FILE="$(dirname "$REG_FILE")/regional_settings_temp.reg"

# Create the oem/registry directory if it doesn't exist
mkdir -p "$(dirname "$REG_FILE")"

# Function to get locale value using locale command
get_locale_value() {
    local category="$1"
    local key="$2"
    local value
    value=$(locale -ck "$category" 2>/dev/null | grep "^${key}=" | cut -d'=' -f2- | sed 's/^"//;s/"$//' | iconv -f UTF-8 -t UTF-8 -c)
    if [ -z "$value" ]; then
        echo "Warning: Could not retrieve $key from $category" >&2
        return 1
    fi
    echo "$value"
}

# Function to convert date format from Linux to Windows
convert_date_format() {
    local linux_format="$1"
    local converted
    converted=$(echo "$linux_format" | sed \
        -e 's/%Y/yyyy/g' \
        -e 's/%y/yyyy/g' \
        -e 's/%m/MM/g' \
        -e 's/%d/dd/g' \
        -e 's/%e/d/g' \
        -e 's/%-m/M/g' \
        -e 's/%-d/d/g' \
        -e 's/[[:space:]]\+/ /g')
    if [[ -z "$converted" || "$converted" == "$linux_format" ]]; then
        echo "Warning: Unrecognized date format '$linux_format'" >&2
        return 1
    fi
    echo "$converted"
}

# Function to escape special characters for registry
escape_for_registry() {
    local input="$1"
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Function to create registry content
create_registry_content() {
    local hive="$1"

    : > "$TEMP_FILE"
    {
        echo "Windows Registry Editor Version 5.00"
        echo
        echo "[${hive}\\Control Panel\\International]"
        [ -n "$DECIMAL_SEP" ] && echo "\"sDecimal\"=\"$DECIMAL_SEP\""
        [ -n "$THOUSAND_SEP" ] && echo "\"sThousand\"=\"$THOUSAND_SEP\""
        [ -n "$CURRENCY_SYMBOL" ] && echo "\"sCurrency\"=\"$CURRENCY_SYMBOL\""
        [ -n "$MON_DECIMAL_SEP" ] && echo "\"sMonDecimalSep\"=\"$MON_DECIMAL_SEP\""
        [ -n "$MON_THOUSAND_SEP" ] && echo "\"sMonThousandSep\"=\"$MON_THOUSAND_SEP\""
        [ -n "$WIN_SHORT_DATE" ] && echo "\"sShortDate\"=\"$WIN_SHORT_DATE\""
        [ -n "$DATE_SEP" ] && echo "\"sDate\"=\"$DATE_SEP\""
        echo "\"sTimeFormat\"=\"HH:mm:ss tt\""
        echo "\"sShortTime\"=\"HH:mm tt\""
        echo "\"iTime\"=\"1\""
        echo "\"iMeasure\"=\"0\""
    } >> "$TEMP_FILE"
}

# Get current locale settings
echo "Current locale: ${LANG:-unknown}"

# Extract locale values
DECIMAL_SEP=$(get_locale_value "LC_NUMERIC" "decimal_point")
THOUSAND_SEP=$(get_locale_value "LC_NUMERIC" "thousands_sep")
CURRENCY_SYMBOL=$(get_locale_value "LC_MONETARY" "currency_symbol")
MON_DECIMAL_SEP=$(get_locale_value "LC_MONETARY" "mon_decimal_point")
MON_THOUSAND_SEP=$(get_locale_value "LC_MONETARY" "mon_thousands_sep")
DATE_FORMAT=$(get_locale_value "LC_TIME" "d_fmt")

# Fallback logic for missing values
if [ -n "$DECIMAL_SEP" ]; then
    if [ -z "$THOUSAND_SEP" ]; then
        if [ "$DECIMAL_SEP" = "." ]; then
            THOUSAND_SEP=","
        elif [ "$DECIMAL_SEP" = "," ]; then
            THOUSAND_SEP="."
        else
            echo "Warning: Cannot infer thousands separator from '$DECIMAL_SEP'" >&2
        fi
    fi
    [ -z "$MON_DECIMAL_SEP" ] && MON_DECIMAL_SEP="$DECIMAL_SEP"
    [ -z "$MON_THOUSAND_SEP" ] && MON_THOUSAND_SEP="$THOUSAND_SEP"
fi

# Convert date format
if [ -n "$DATE_FORMAT" ]; then
    WIN_SHORT_DATE=$(convert_date_format "$DATE_FORMAT")
fi

# Determine date separator
if [ -n "$WIN_SHORT_DATE" ]; then
    DATE_SEP="/"
    [[ "$WIN_SHORT_DATE" == *"-"* ]] && DATE_SEP="-"
    [[ "$WIN_SHORT_DATE" == *"."* ]] && DATE_SEP="."
fi

# Escape for registry
DECIMAL_SEP=$(escape_for_registry "$DECIMAL_SEP")
THOUSAND_SEP=$(escape_for_registry "$THOUSAND_SEP")
CURRENCY_SYMBOL=$(escape_for_registry "$CURRENCY_SYMBOL")
MON_DECIMAL_SEP=$(escape_for_registry "$MON_DECIMAL_SEP")
MON_THOUSAND_SEP=$(escape_for_registry "$MON_THOUSAND_SEP")
DATE_SEP=$(escape_for_registry "$DATE_SEP")

# Display what was extracted
echo
echo "Extracted settings:"
echo "  Decimal separator: '$DECIMAL_SEP'"
echo "  Thousands separator: '$THOUSAND_SEP'"
echo "  Currency symbol: '$CURRENCY_SYMBOL'"
echo "  Currency decimal separator: '$MON_DECIMAL_SEP'"
echo "  Currency thousands separator: '$MON_THOUSAND_SEP'"
echo "  Short date format: '$WIN_SHORT_DATE'"
echo "  Date separator: '$DATE_SEP'"
echo

# Create registry data, write to HKU\DefaultUser as this is what is used in the install.bat to apply this to HKEY_CURRENT_USER for all users 
create_registry_content "HKEY_USERS\\DefaultUser"

# Convert to UTF-16LE with BOM
if ! printf "\xFF\xFE" > "$REG_FILE" || ! iconv -f UTF-8 -t UTF-16LE "$TEMP_FILE" >> "$REG_FILE"; then
    echo "Error: Failed to convert registry content to UTF-16LE with BOM" >&2
    rm -f "$TEMP_FILE"
    exit 1
fi
rm -f "$TEMP_FILE"

# Confirm result
echo "Registry file created successfully at: $REG_FILE"
