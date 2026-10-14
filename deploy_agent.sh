handle_interrupt() {
    trap '' INT TSTP
    echo
    echo "[!] Deployment interrupted by user."
    if [ -n "$PROJECT_DIR" ] && [ -d "$BASE_DIR/$PROJECT_DIR" ]; then
        local zip_name="${PROJECT_DIR}_archive.zip"
        echo "[!] Archiving incomplete project into $zip_name ..."
        if (cd "$BASE_DIR" && zip -rq "$zip_name" "$PROJECT_DIR"); then
            echo "[+] Archive created: $BASE_DIR/$zip_name"
            rm -rf "${BASE_DIR:?}/$PROJECT_DIR"
            echo "[+] Incomplete directory $PROJECT_DIR removed."
        else
            echo "[x] Failed to create archive. Incomplete directory left in place."
        fi
    else
        echo "[!] Nothing had been created yet. Nothing to archive."
    fi
    echo "[!] Session closed."
    exit 130
}

preflight_checks() {
    echo "[*] Running pre-flight checks..."
    local missing=0
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[x] python3 is not installed."
        missing=1
    else
        echo "[+] Found: $(python3 --version 2>&1)"
    fi
    if ! command -v zip >/dev/null 2>&1; then
        echo "[x] zip is not installed."
        missing=1
    else
        echo "[+] Found: zip"
    fi
    if [ ! -d "$TEMPLATE_DIR" ]; then
        echo "[x] templates/ directory not found at $TEMPLATE_DIR"
        missing=1
    else
        local f
        for f in attendance_checker.py assets.csv config.json; do
            if [ ! -f "$TEMPLATE_DIR/$f" ]; then
                echo "[x] Missing template: templates/$f"
                missing=1
            fi
        done
    fi
    if [ ! -w "$BASE_DIR" ]; then
        echo "[x] No write permission in $BASE_DIR"
        missing=1
    fi
    if [ "$missing" -ne 0 ]; then
        echo "[x] Pre-flight checks failed. Aborting."
        return 1
    fi
    echo "[+] Pre-flight checks passed."
    return 0
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

run_app() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "[x] Directory $dir does not exist. Deploy first."
        return 1
    fi
    if [ ! -f "$dir/attendance_checker.py" ]; then
        echo "[x] attendance_checker.py not found in $dir."
        return 1
    fi
    echo "[*] Starting attendance checker in $dir ..."
    (cd "$dir" && python3 attendance_checker.py)
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "[x] Application exited with status $status."
        return "$status"
    fi
    echo "[+] Application finished successfully."
    return 0
}

run_feature() {
    ask_project_name || return 1
    run_app "$BASE_DIR/attendance_tracker_${PROJECT_NAME}"
}

