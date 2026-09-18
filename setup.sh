#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/variables.env"
MAIN_SCRIPT="$SCRIPT_DIR/backup_tracker.sh"

echo "======================================================================"
echo "  WARNING: Do not move this folder or its files after configuring."
echo "  backup.service and 10-launch.sh point to these absolute paths."
echo "  If you move it, re-run ./setup.sh."
echo "======================================================================"
echo

# Values (reusing existing configuration as defaults)
LOGIN_USER="${USER:-$(whoami)}"
LOGIN_IP="localhost"
LOGIN_PORT=22
HAS_CONFIG=0

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    LOGIN_USER="${USER:-$LOGIN_USER}"
    LOGIN_IP="${IP:-$LOGIN_IP}"
    LOGIN_PORT="${SSH_PORT:-22}"
    HAS_CONFIG=1
fi

ask() {
    local prompt="$1" default="$2"
    local value
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
}

require() {
    local prompt="$1" value
    while [[ -z "${value:-}" ]]; do
        read -r -p "$prompt: " value
    done
    echo "$value"
}

echo "=== Backup Tracker setup ==="
echo

if [[ $HAS_CONFIG -eq 1 ]]; then
    TRACKING_FOLDER=$(ask "Folder to track" "$TRACKING_FOLDER")
else
    TRACKING_FOLDER=$(require "Folder to track")
fi

while [[ ! -d "$TRACKING_FOLDER" ]]; do
    echo "WARNING: '$TRACKING_FOLDER' does not exist, enter a valid folder."
    TRACKING_FOLDER=$(require "Folder to track")
done

if [[ $HAS_CONFIG -eq 1 ]]; then
    BACKUP_FOLDER=$(ask "Folder where to store the backups" "$BACKUP_FOLDER")
else
    BACKUP_FOLDER=$(require "Folder where to store the backups on the server")
fi

LOGIN_IP=$(ask "Server IP" "$LOGIN_IP")
LOGIN_USER=$(ask "SSH user" "$LOGIN_USER")
LOGIN_PORT=$(ask "SSH port" "$LOGIN_PORT")

echo
while true; do
    read -r -p "Set up backup.service (systemd)? [y/N] " USE_SERVICE
    USE_SERVICE="${USE_SERVICE,,}"
    [[ -z "$USE_SERVICE" ]] && USE_SERVICE="n"
    [[ "$USE_SERVICE" == "y" || "$USE_SERVICE" == "n" ]] && break
done

echo
echo "=== Summary ==="
echo "Folder to track    : $TRACKING_FOLDER"
echo "Backup folder      : $BACKUP_FOLDER"
echo "Server             : $LOGIN_USER@$LOGIN_IP:$LOGIN_PORT"
echo "systemd service    : $USE_SERVICE"
echo

read -r -p "Write the files? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Cancelled."
    exit 0
fi

cat > "$ENV_FILE" <<EOF
TRACKING_FOLDER="$TRACKING_FOLDER"

BACKUP_FOLDER="$BACKUP_FOLDER"
SNAPSHOTS="$BACKUP_FOLDER/snapshots"

IP="$LOGIN_IP"
USER="$LOGIN_USER"
REMOTE="$LOGIN_USER@$LOGIN_IP"
SSH_PORT=$LOGIN_PORT
EOF

if [[ "$USE_SERVICE" == "y" ]]; then
    cat > "$SCRIPT_DIR/backup.service" <<EOF
# /etc/systemd/system/backup.service

[Unit]
Description=Backup script

[Service]
Type=oneshot
User=$LOGIN_USER
Group=$LOGIN_USER
ExecStart=/bin/bash $MAIN_SCRIPT
EOF
fi

if [[ "$USE_SERVICE" == "y" ]]; then
    LAUNCH_CMD='systemctl start backup.service'
else
    LAUNCH_CMD="runuser -u $LOGIN_USER -- $MAIN_SCRIPT"
fi

cat > "$SCRIPT_DIR/10-launch.sh" <<EOF
#!/bin/bash

# /etc/NetworkManager/dispatcher.d/10-launch.sh

if [[ "\$2" == "up" ]]; then
	$LAUNCH_CMD
fi
EOF

chmod +x "$SCRIPT_DIR/10-launch.sh"

echo
echo "Created files:"
echo "  $ENV_FILE"
echo "  $SCRIPT_DIR/10-launch.sh"
[[ "$USE_SERVICE" == "y" ]] && echo "  $SCRIPT_DIR/backup.service"

echo
echo "Next steps:"
echo
echo "1) Copy the files:"
echo "   sudo cp $SCRIPT_DIR/10-launch.sh /etc/NetworkManager/dispatcher.d/"
[[ "$USE_SERVICE" == "y" ]] && echo "   sudo cp $SCRIPT_DIR/backup.service /etc/systemd/system/"
echo

if [[ "$USE_SERVICE" == "y" ]]; then
    echo "2) Run these commands to fix SELinux errors:"
    echo "   sudo setsebool -P rsync_client 1"
    echo "   sudo setsebool -P rsync_export_all_ro 1"
    echo
    echo "3) Reload systemd and start the service:"
    echo "   sudo systemctl daemon-reload"
    echo "   sudo systemctl restart backup.service"
	echo
	echo "4) To view the logs run journalctl -u backup.service"
fi
