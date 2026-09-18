#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/variables.env"
MAIN_SCRIPT="$SCRIPT_DIR/backup_tracker.sh"

echo "======================================================================"
echo "  AVISO: NO muevas esta carpeta ni sus archivos despues de configurar."
echo "  backup.service y 10-launch.sh apuntaran a estas rutas absolutas."
echo "  Si la mueves, vuelve a ejecutar ./setup.sh."
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
    TRACKING_FOLDER=$(ask "Carpeta a rastrear" "$TRACKING_FOLDER")
else
    TRACKING_FOLDER=$(require "Carpeta a rastrear")
fi

while [[ ! -d "$TRACKING_FOLDER" ]]; do
    echo "AVISO: '$TRACKING_FOLDER' no existe, introduce una carpeta valida."
    TRACKING_FOLDER=$(require "Carpeta a rastrear")
done

if [[ $HAS_CONFIG -eq 1 ]]; then
    BACKUP_FOLDER=$(ask "Carpeta donde guardar los backups" "$BACKUP_FOLDER")
else
    BACKUP_FOLDER=$(require "Carpeta donde guardar los backups en el servidor")
fi

LOGIN_IP=$(ask "IP del servidor" "$LOGIN_IP")
LOGIN_USER=$(ask "Usuario SSH" "$LOGIN_USER")
LOGIN_PORT=$(ask "Puerto SSH" "$LOGIN_PORT")

echo
while true; do
    read -r -p "Configurar backup.service (systemd)? [y/N] " USE_SERVICE
    USE_SERVICE="${USE_SERVICE,,}"
    [[ -z "$USE_SERVICE" ]] && USE_SERVICE="n"
    [[ "$USE_SERVICE" == "y" || "$USE_SERVICE" == "n" ]] && break
done

echo
echo "=== Resumen ==="
echo "Carpeta a rastrear : $TRACKING_FOLDER"
echo "Carpeta de backups : $BACKUP_FOLDER"
echo "Servidor           : $LOGIN_USER@$LOGIN_IP:$LOGIN_PORT"
echo "Servicio systemd   : $USE_SERVICE"
echo

read -r -p "Escribir los archivos? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Cancelado."
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
echo "Archivos creados:"
echo "  $ENV_FILE"
echo "  $SCRIPT_DIR/10-launch.sh"
[[ "$USE_SERVICE" == "y" ]] && echo "  $SCRIPT_DIR/backup.service"

echo
echo "Siguientes pasos:"
echo
echo "1) Copiar los archivos:"
echo "   sudo cp $SCRIPT_DIR/10-launch.sh /etc/NetworkManager/dispatcher.d/"
[[ "$USE_SERVICE" == "y" ]] && echo "   sudo cp $SCRIPT_DIR/backup.service /etc/systemd/system/"
echo

if [[ "$USE_SERVICE" == "y" ]]; then
    echo "2) Ejecuta estos comandos para eliminar los errores de SELinux:"
    echo "   sudo setsebool -P rsync_client 1"
    echo "   sudo setsebool -P rsync_export_all_ro 1"
    echo
    echo "3) Recarga systemd y arranca el servicio:"
    echo "   sudo systemctl daemon-reload"
    echo "   sudo systemctl restart backup.service"
	echo
	echo "4) Para ver los logs ejecuta journalctl -u backup.service"
fi
