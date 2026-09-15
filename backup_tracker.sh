#!/bin/bash

set -euo pipefail

BACKUP_FOLDER="/home/hvidal/backups/backup/"
TRACKING_FOLDER="/home/hvidal/backups/org/"
SNAPSHOTS="$BACKUP_FOLDER/snapshots"

INTERVAL_DAYS=5

PREVIOUS=$(find "$SNAPSHOTS" \
    -mindepth 1 -maxdepth 1 -type d \
    | sort | tail -n 1)

# Parse the lastest snapshot date
if [[ -n "$PREVIOUS" ]]; then

    PREVIOUS_NAME=$(basename "$PREVIOUS")
    PREVIOUS_DATE="${PREVIOUS_NAME//_/ }"
    PREVIOUS_DATE="${PREVIOUS_DATE:0:10} ${PREVIOUS_DATE:11:2}:${PREVIOUS_DATE:14:2}:${PREVIOUS_DATE:17:2}"

    if ! PREVIOUS_TIME=$(date -d "$PREVIOUS_DATE" +%s 2>/dev/null); then
		# if invalid name -> new snapshot
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


	CHANGES=$(rsync -ai \
		--dry-run \
		"$TRACKING_FOLDER/" \
		"$PREVIOUS/"
	)

	if [[ -z "$CHANGES" ]]; then
		exit 0
	fi
fi

# Create a new snapshot
SNAPSHOT="$SNAPSHOTS/$(date '+%Y-%m-%d_%H-%M-%S')"

mkdir -p "$SNAPSHOT"

if [[ -n "$PREVIOUS" ]]; then
    rsync -a \
		--delete \
        --link-dest="$PREVIOUS" \
        "$TRACKING_FOLDER/" \
        "$SNAPSHOT/"
else
    rsync -a \
		--delete \
        "$TRACKING_FOLDER/" \
        "$SNAPSHOT/"
fi

