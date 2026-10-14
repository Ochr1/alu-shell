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

