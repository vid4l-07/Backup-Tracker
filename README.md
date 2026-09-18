# Backup Tracker

Incremental backup (snapshot) system for a local folder to a remote server over SSH, with interactive restore and automatic rotation.

## Features

- **Incremental snapshots** using `rsync` + `--link-dest` (hard links), saving disk space and time.
- **Automatic rotation**: keeps only the 5 most recent snapshots.
- **Change detection**: skips creating a new snapshot when nothing has changed.
- **Temporary snapshots**: copies are written to a `.tmp` directory and renamed only on successful completion, preventing corrupt or partial snapshots.
- **Interactive restore** with a preview of changes (added, modified, deleted) and confirmation before overwriting.
- **Automated setup**: `setup.sh` generates the config file and optional `systemd` / NetworkManager dispatcher files.

## Requirements

- `bash`, `rsync`, `ssh`, `ping`
- SSH key access to the remote server (no password prompts)
- `rsync` installed on the remote server

## Setup

Run the setup script. It asks for the folder to track, the backup folder, the server credentials, and whether to create the systemd service:

```bash
./setup.sh
```

The script writes `variables.env`, `10-launch.sh` and, optionaly, `backup.service`, then prints the remaining steps (copying the files to their system locations, and any SELinux/systemd commands).

> [!WARNING]
> Do not move the project folder after running setup. `backup.service` and `10-launch.sh` reference absolute paths. If you move it, re-run `./setup.sh`.

You can also edit `variables.env` manually:

| Variable          | Description                                  | Example                          |
|-------------------|----------------------------------------------|----------------------------------|
| `TRACKING_FOLDER` | Local folder to back up                      | `/path/to/folder`                |
| `BACKUP_FOLDER`   | Base folder on the remote server             | `/remote/path/backup`            |
| `SNAPSHOTS`       | Folder where snapshots are stored            | `$BACKUP_FOLDER/snapshots`       |
| `IP`              | Host of the remote server                    | `localhost`                      |
| `USER`            | SSH user                                     | `user`                           |
| `REMOTE`          | Combined user and host (`USER@IP`)           | `user@localhost`                 |
| `SSH_PORT`        | SSH port                                     | `22`                             |

> `INTERVAL_DAYS` in `backup_tracker.sh` defines the minimum interval (in days) between snapshots. Currently set to `0` (an interval check is performed, but the threshold is disabled); set it to the desired number of days to enable it.

## Usage

### Create a backup

```bash
./backup_tracker.sh
```

The script:
1. Verifies connectivity (ping + SSH).
2. Cleans up abandoned temporary snapshots.
3. Compares the local folder with the latest snapshot; exits if nothing changed.
4. Creates an incremental snapshot (`--delete`), renames it from `.tmp` to its final name, and rotates old ones (keeps max. 5).

### Restore a snapshot

Show available snapshots and the changes they contain:

```bash
./restore.sh
```

Restore a specific snapshot:

```bash
./restore.sh 2026-09-18_12:00:00
```

It shows the changes (added, modified, deleted) and asks for confirmation before overwriting the local folder.

## Automation

### systemd (oneshot service)

`setup.sh` generates `backup.service`. Copy it and load it:

```bash
sudo cp backup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start backup.service
```

Watch the logs:

```bash
journalctl -u backup.service
```

> [!Note]
> On systems with SELinux you may need:

```bash
sudo setsebool -P rsync_client 1
sudo setsebool -P rsync_export_all_ro 1
```

### NetworkManager dispatcher

`setup.sh` generates `10-launch.sh`, so the backup runs automatically when the network comes up:

```bash
sudo cp 10-launch.sh /etc/NetworkManager/dispatcher.d/
```

## How snapshots work

Each snapshot is a full directory thanks to hard links; the extra disk usage between consecutive snapshots is minimal. Unchanged files are hard-linked to the previous snapshot, and `--delete` removes files that no longer exist in the tracked folder.
