#!/bin/bash

set -euo pipefail

log() {
    echo "$(date '+%Y-%m-%d_%H:%M:%S') - $*"
}

error() {
    echo "$(date '+%Y-%m-%d_%H:%M:%S') - $*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variables.env"

if ! ping -c 1 -W 5 "$IP" >/dev/null 2>&1; then
	exit 1
fi

# Check connectivity
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$REMOTE" true 2>/dev/null; then
	error "Could not connect via SSH"
    exit 1
fi

log "SSH connection established"

# Create backups folder
ssh -p "$SSH_PORT" "$REMOTE" "mkdir -p '$SNAPSHOTS'"

# Remove abandoned temporary snapshots
ssh -p "$SSH_PORT" "$REMOTE" "find '$SNAPSHOTS' \
    -mindepth 1 -maxdepth 1 \
    -type d \
    -name '*.tmp' \
    -exec rm -rf {} +"

# Previous snapshot
PREVIOUS=$(
	ssh -p "$SSH_PORT" "$REMOTE" "find '$SNAPSHOTS' \
    -mindepth 1 -maxdepth 1 -type d \
    | sort | tail -n 1"
)

# Parse the lastest snapshot date
if [[ -n "$PREVIOUS" ]]; then
    PREVIOUS_NAME=$(basename "$PREVIOUS")
	PREVIOUS_DATE="${PREVIOUS_NAME//_/ }"

    if ! PREVIOUS_TIME=$(date -d "$PREVIOUS_DATE" +%s 2>/dev/null); then
		# Invalid snapshot name -> remove it and create a new snapshot
		error "Invalid snapshot name: $PREVIOUS_NAME, removing it"

		ssh -p "$SSH_PORT" "$REMOTE" "rm -rf '$PREVIOUS'"
        PREVIOUS=""  
    fi
fi


# Check if the required time has passed and there are changes
if [[ -n "$PREVIOUS" ]]; then
	CURRENT_TIME=$(date +%s)
	ELAPSED=$((CURRENT_TIME - PREVIOUS_TIME))
	INTERVAL=$((INTERVAL_DAYS * 86400))

	if (( ELAPSED < INTERVAL )); then
		exit 0
	fi


	CHANGES=$(
		rsync -ai \
		--dry-run \
		-e "ssh -p $SSH_PORT" \
		"$TRACKING_FOLDER/" \
		"$REMOTE:$PREVIOUS/" \
		| grep -v '^\.d' || true
	)

	if [[ -z "$CHANGES" ]]; then
		log "No changes found"
		exit 0
	fi

	CHANGE_COUNT=$(printf '%s\n' "$CHANGES" | wc -l)
	log "Changes detected: $CHANGE_COUNT"
fi

# Create a new snapshot
SNAPSHOT="$SNAPSHOTS/$(date '+%Y-%m-%d_%H:%M:%S')"
TEMP_SNAPSHOT="$SNAPSHOT.tmp"

ssh -p "$SSH_PORT" "$REMOTE" "mkdir -p '$TEMP_SNAPSHOT'"

if [[ -n "$PREVIOUS" ]]; then
	log "Creating incremental snapshot: $SNAPSHOT"
    rsync -a \
		--delete \
		-e "ssh -p $SSH_PORT" \
        --link-dest="$PREVIOUS" \
        "$TRACKING_FOLDER/" \
        "$REMOTE:$TEMP_SNAPSHOT/"
else
	log "Creating full snapshot: $SNAPSHOT"
    rsync -a \
		--delete \
		-e "ssh -p $SSH_PORT" \
        "$TRACKING_FOLDER/" \
        "$REMOTE:$TEMP_SNAPSHOT/"
fi

ssh -p "$SSH_PORT" "$REMOTE" "mv '$TEMP_SNAPSHOT' '$SNAPSHOT'"
log "Backup completed successfully"

# Keep only the 5 most recent snapshots
SNAPSHOT_COUNT=$(
	ssh -p "$SSH_PORT" "$REMOTE" "find '$SNAPSHOTS' \
    -mindepth 1 -maxdepth 1 -type d \
    | wc -l"
)

if (( SNAPSHOT_COUNT > 5 )); then
	log "Removing $(SNAPSHOT_COUNT - 5) old snapshots"

    ssh -p "$SSH_PORT" "$REMOTE" "find '$SNAPSHOTS' \
        -mindepth 1 -maxdepth 1 -type d \
        | sort \
        | head -n $((SNAPSHOT_COUNT - 5)) \
        | xargs rm -rf"
fi
