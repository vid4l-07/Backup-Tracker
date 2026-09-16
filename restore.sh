#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variables.env"

# Check SSH connection
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$REMOTE" true 2>/dev/null; then
    echo "Could not connect to server"
    exit 1
fi

# Check snapshot argument
if [[ $# -ne 1 ]]; then
	echo "Snapshots: "
	ssh -p "$SSH_PORT" "$REMOTE" "ls '$SNAPSHOTS'"
    exit 1
fi

# Check that the snapshot exists
SNAPSHOT="$1"

if ! ssh -p "$SSH_PORT" "$REMOTE" \
    "find '$SNAPSHOTS' -mindepth 1 -maxdepth 1 -type d -printf '%f\n'" | grep -Fxq -- "$SNAPSHOT"; then

    echo "Snapshot not found: $SNAPSHOT"
    exit 1
fi

REMOTE_SNAPSHOT="$SNAPSHOTS/$SNAPSHOT"

CHANGES=$(
    rsync -ai \
        --delete \
        --dry-run \
        -e "ssh -p $SSH_PORT" \
        "$REMOTE:$REMOTE_SNAPSHOT/" \
        "$TRACKING_FOLDER/"
)

if [[ -z "$CHANGES" ]];then
	echo "No changes"
	exit 0
fi

echo -e "Changes:\n"

DELETED=()

while IFS= read -r LINE; do
    if [[ "$LINE" == "*deleting "* ]]; then
        DELETED+=("${LINE#*deleting }")
    fi

    if [[ "$LINE" == ">f+++++++++ "* ]]; then
        echo "  Added:    ${LINE#*>f+++++++++ }"

    elif [[ "$LINE" == ">f"* ]]; then
        echo "  Modified: ${LINE:12}"
    fi
done <<< "$CHANGES"

for FILE in "${DELETED[@]}"; do
    IS_CHILD=false

    for PARENT in "${DELETED[@]}"; do
		if [[ "$FILE" != "$PARENT" && "$FILE" == "$PARENT"* ]]; then
            IS_CHILD=true
            break
        fi
    done

    if [[ "$IS_CHILD" == false ]]; then
        echo "  Deleted:  $FILE"
    fi
done

echo
read -r -p "Restore snapshot '$SNAPSHOT' to '$TRACKING_FOLDER'? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Restore snapshot
rsync -a \
	--delete \
    -e "ssh -p $SSH_PORT" \
    "$REMOTE:$REMOTE_SNAPSHOT/" \
    "$TRACKING_FOLDER/"
