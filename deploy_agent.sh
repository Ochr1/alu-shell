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

