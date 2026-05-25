#!/bin/bash
set -euo pipefail

log()  { echo "[$(date '+%H:%M:%S')] >>> $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

[ "$#" -ne 1 ] && fail "Usage: $0 <target>"

TARGET=${1}
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BASE_DIR="$HOME/emperion/$TARGET"
RELEASE_PATH="$BASE_DIR/releases/$TIMESTAMP"
ARTIFACT_FILE="$BASE_DIR/artifact.tar.gz"
KEEP_RELEASES=2

SUCCESS=false

# Run a Magento CLI command inside the ephemeral deploy container
magento() {
  ${RELEASE_PATH}/bin/magento "$@"
}

# Explicitly check if Magento command is successful
check_magento_status() {
  local cmd=$1
  local status=0

  magento "$cmd" > /dev/null 2>&1 || status=$?

  echo "$status"
}

# --- Automatic cleanup ---
function cleanup {
  trap - EXIT

  log "Cleaning up temporary files..."
  # rm -f "${BASE_DIR}/artifact.tar.gz"
  # rm -f "${BASE_DIR}/remote-deploy.sh"

  # --- Disable maintenance mode ---
 
  log "Disabling maintenance mode"
  [ -L "$BASE_DIR/current" ] && rm -f "$(readlink -f "$BASE_DIR/current")/var/.maintenance.flag"
  magento cache:flush || echo "Could not flush cache"

  # --- Cleanup old releases ---
 
  if [ "$SUCCESS" = true ]; then
    log "Cleaning up old releases (keeping $KEEP_RELEASES)"
    ls -1dt "$BASE_DIR/releases"/*/ \
      | tail -n +$((KEEP_RELEASES + 1)) \
      | xargs -r rm -rf
    log "Deploy complete: $TIMESTAMP is now live"
  else
    log "Deployment failed!"
    if [ -d "$RELEASE_PATH" ]; then
        log "Removing failed release directory: $RELEASE_PATH"
        # rm -rf "$RELEASE_PATH"
    fi
  fi
}
trap cleanup EXIT # Execute cleanup on script exit

# --- Validate artifact ---
log "Deploying release: $TIMESTAMP"
[ -f "$ARTIFACT_FILE" ] || fail "Artifact not found: $ARTIFACT_FILE"
 
# --- Prepare release directory ---
log "Creating release directory"
mkdir -p "$RELEASE_PATH"

log "Extracting artifact"
tar -xzpf "$ARTIFACT_FILE" -C "$RELEASE_PATH" --strip-components=1
 
# --- Shared files and directories ---

log "Linking shared files and directories"
cd "$RELEASE_PATH"

# Files
mkdir -p "app/etc"
ln -sfn ../../../../shared/app/etc/env.php app/etc/env.php

# Directories (remove placeholder if extracted from artifact, then symlink)
for dir in \
  "pub/media" \
  "pub/sitemap" \
  "var/backups" \
  "var/export" \
  "var/import" \
  "var/import_history" \
  "var/importexport" \
  "var/log" \
  "var/report" \
  "var/session"
do
  mkdir -p "$BASE_DIR/shared/$dir"
  rm -rf "$dir"
  mkdir -p "$(dirname "$dir")"

  RELATIVE_DEPTH=$(echo "$dir" | awk -F'/' '{for(i=1;i<=NF;i++) printf "../"}')
  ln -sfn "${RELATIVE_DEPTH}../shared/$dir" "$dir"
done
mkdir -p var/cache var/page_cache var/tmp
 
# --- Enable maintenance mode ---
 
log "Enabling maintenance mode"
if [ -L "$BASE_DIR/current" ]; then
  touch "$(readlink -f "$BASE_DIR/current")/var/.maintenance.flag"
fi
 
# --- Database and config ---
 
log "Checking app config and database"

CONFIG_STATUS=$(check_magento_status "app:config:status") || fail "Internal script error"
if [ "$CONFIG_STATUS" -eq 2 ]; then
  log "Config change detected. Importing..."
  magento app:config:import --no-interaction
elif [ "$CONFIG_STATUS" -ne 0 ]; then
  fail "Magento config status returned unexpected error: $CONFIG_STATUS"
fi

DB_STATUS=$(check_magento_status "setup:db:status") || fail "Internal script error"
if [ "$DB_STATUS" -eq 2 ]; then
  log "DB update needed. Upgrading..."
  magento setup:upgrade --keep-generated --no-interaction
elif [ "$DB_STATUS" -ne 0 ]; then
  fail "Magento DB status returned unexpected error: $DB_STATUS"
fi

SUCCESS=true

# --- Flip symlink ---
 
log "Switching current symlink to $TIMESTAMP"
cd "$BASE_DIR"
ln -sfn "./releases/$TIMESTAMP" current.next
mv -Tf current.next current

