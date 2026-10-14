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

deploy_project() {
    preflight_checks || return 1

    trap handle_interrupt INT TSTP

    ask_project_name || { trap - INT TSTP; return 1; }
    local dir="attendance_tracker_${PROJECT_NAME}"
    local path="$BASE_DIR/$dir"

    if [ -e "$path" ]; then
        local answer
        read -r -p "Directory $dir already exists. Overwrite? (y/N): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            rm -rf "${path:?}" || { echo "[x] Could not remove $dir."; trap - INT TSTP; return 1; }
        else
            echo "[x] Aborting: $dir already exists."
            trap - INT TSTP
            return 1
        fi
    fi

    PROJECT_DIR="$dir"

    echo "[*] Creating directory structure..."
    if ! mkdir -p "$path/Helpers" "$path/reports"; then
        echo "[x] Failed to create directories (permission denied?)."
        rm -rf "${path:?}"
        PROJECT_DIR=""
        trap - INT TSTP
        return 1
    fi

    cp "$TEMPLATE_DIR/attendance_checker.py" "$path/attendance_checker.py" || { echo "[x] Failed to copy attendance_checker.py"; rm -rf "${path:?}"; PROJECT_DIR=""; trap - INT TSTP; return 1; }
    cp "$TEMPLATE_DIR/config.json" "$path/Helpers/config.json" || { echo "[x] Failed to copy config.json"; rm -rf "${path:?}"; PROJECT_DIR=""; trap - INT TSTP; return 1; }

    local choice
    while true; do
        echo "Roster options:"
        echo "  A) Copy from template"
        echo "  B) Generate fresh roster"
        read -r -p "Choose A or B: " choice
        case "$choice" in
            [Aa]) build_roster_copy "$path/Helpers/assets.csv" && break ;;
            [Bb]) build_roster_generate "$path/Helpers/assets.csv" && break ;;
            *) echo "[x] Invalid choice." ;;
        esac
    done

    sed -i.bak -E "s/(\"total_sessions\":[[:space:]]*)[0-9]+/\1$SESSIONS/" "$path/Helpers/config.json" && rm -f "$path/Helpers/config.json.bak"
    echo "[+] total_sessions set to $SESSIONS to match the roster."

    update_thresholds "$path/Helpers/config.json" || echo "[!] Continuing with existing thresholds."

    chmod +x "$path/attendance_checker.py"
    chmod 600 "$path/Helpers/config.json"
    echo "[+] Permissions set:"
    ls -l "$path/attendance_checker.py" "$path/Helpers/config.json"

    trap - INT TSTP
    PROJECT_DIR=""

    echo "[+] Deployment complete: $dir"
    echo "[*] Verifying deployment by running the application..."
    run_app "$path"
}

