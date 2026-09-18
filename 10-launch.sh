#!/bin/bash

# /etc/NetworkManager/dispatcher.d/10-launch.sh

if [[ "$2" == "up" ]]; then
	# systemctl start backup.service  # with logs (journalctl -u backup.service)
	runuser -u hvidal -- /home/hvidal/datos_lin/programacion/scripts/backup_tracker/backup_tracker.sh  # without but more simple
fi
