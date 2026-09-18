#!/bin/bash

# /etc/NetworkManager/dispatcher.d/10-launch.sh

if [[ "$2" == "up" ]]; then
	systemctl start backup.service
fi
