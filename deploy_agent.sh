build_roster_copy() {
    local target="$1"
    local available count
    available=$(( $(wc -l < "$TEMPLATE_DIR/assets.csv") - 1 ))
    while true; do
        read -r -p "How many students to copy from template (1-$available)? " count
        if is_positive_int "$count" && [ "$count" -le "$available" ]; then
            break
        fi
        echo "[x] Enter a whole number between 1 and $available."
    done
    head -n $((count + 1)) "$TEMPLATE_DIR/assets.csv" > "$target" || return 1
    echo "[+] Copied $count students (plus header) from template."
    SESSIONS=5
}

build_roster_generate() {
    local target="$1"
    local max=${#NAMES[@]}
    local count i
    while true; do
        read -r -p "How many students to generate (1-$max)? " count
        if is_positive_int "$count" && [ "$count" -le "$max" ]; then
            break
        fi
        echo "[x] Enter a whole number between 1 and $max."
    done
    {
        echo "Email,Names,Attendance Count,Absence Count"
        for ((i = 0; i < count; i++)); do
            echo "${EMAILS[$i]},${NAMES[$i]},0,0"
        done
    } > "$target" || return 1
    echo "[+] Generated $count students with zeroed counts."
    SESSIONS=1
}

update_thresholds() {
    local config="$1"
    local answer warn fail
    read -r -p "Update attendance alert thresholds? (y/N): " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "[*] Keeping default thresholds."
        return 0
    fi
    while true; do
        read -r -p "Warning threshold [75]: " warn
        warn="${warn:-75}"
        if [[ "$warn" =~ ^[0-9]+$ ]] && [ "$warn" -ge 0 ] && [ "$warn" -le 100 ]; then
            break
        fi
        echo "[x] Enter a number between 0 and 100."
    done
    while true; do
        read -r -p "Failure threshold [50]: " fail
        fail="${fail:-50}"
        if [[ "$fail" =~ ^[0-9]+$ ]] && [ "$fail" -ge 0 ] && [ "$fail" -le 100 ]; then
            if [ "$fail" -lt "$warn" ]; then
                break
            fi
            echo "[x] Failure threshold must be lower than warning ($warn)."
        else
            echo "[x] Enter a number between 0 and 100."
        fi
    done
    sed -i.bak -E "s/(\"warning\":[[:space:]]*)[0-9]+/\1$warn/; s/(\"failure\":[[:space:]]*)[0-9]+/\1$fail/" "$config" || {
        echo "[x] Failed to update config.json"
        return 1
    }
    rm -f "$config.bak"
    echo "[+] Thresholds updated: warning=$warn, failure=$fail"
}

