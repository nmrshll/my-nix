# The App entry point stays alive while the real browser runs, so both hooks
# execute without a polling worker. apply-pending rechecks processes and locks.
apply_pending() {
  [[ -f "$BRAVE_SETTINGS_STATE_DIR/pending.json" ]] || return 0
  if ! (
    umask 077
    "$BRAVE_SETTINGS_SYNC" apply-pending \
      --state-dir "$BRAVE_SETTINGS_STATE_DIR" \
      --brave-data-dir "$BRAVE_SETTINGS_DATA_DIR" \
      >>"$BRAVE_SETTINGS_STATE_DIR/brave-settings.log" 2>&1
  ); then
    printf 'Brave settings remain queued; see %s/brave-settings.log\n' \
      "$BRAVE_SETTINGS_STATE_DIR" >&2
  fi
}

apply_pending
browser_status=0
"$BRAVE_SETTINGS_BROWSER" "$@" || browser_status=$?
apply_pending
exit "$browser_status"
