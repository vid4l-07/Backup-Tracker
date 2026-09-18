# Backup Tracker

Sistema de copias de seguridad incremental (snapshots) de una carpeta local hacia un servidor remoto vía SSH, con restauración interactiva y rotación automática.

## Características

- **Snapshots incrementales** mediante `rsync` + `--link-dest` (hard links), ahorrando espacio y tiempo.
- **Rotación automática**: conserva únicamente los 5 snapshots más recientes.
- **Comprobación de conectividad** previa (ping + SSH) antes de iniciar la copia.
- **Detección de cambios**: omite la creación de un nuevo snapshot si no hay modificaciones.
- **Snapshots temporales**: las copias se realizan en un directorio `.tmp` y se renombran solo al terminar correctamente, evitando snapshots corruptos o a medias.
- **Restauración interactiva** con vista previa de cambios (añadidos, modificados, eliminados) y confirmación.
- Preparado para ejecutarse como servicio **systemd** o desde **NetworkManager dispatcher**.

## Requisitos

- `bash`, `rsync`, `ssh`, `ping`
- Acceso SSH por clave al servidor remoto

## Configuración

Edita `variables.env`:

| Variable          | Descripción                                  | Ejemplo                          |
|-------------------|----------------------------------------------|----------------------------------|
| `TRACKING_FOLDER` | Carpeta local a respaldar                    | `/ruta/a/la/carpeta/`            |
| `BACKUP_FOLDER`   | Carpeta base en el servidor remoto           | `/ruta/remota/backup`            |
| `SNAPSHOTS`       | Carpeta donde se guardan los snapshots       | `$BACKUP_FOLDER/snapshots`       |
| `IP`              | Host del servidor remoto                     | `localhost`                      |
| `USER`            | Usuario SSH                                  | `hvidal`                         |
| `REMOTE`          | Usuario y host combinados (`USER@IP`)        | `hvidal@localhost`               |
| `SSH_PORT`        | Puerto SSH                                   | `22`                             |

> La variable `INTERVAL_DAYS` en `backup_tracker.sh` define el intervalo mínimo (en días) entre snapshots.

## Uso

### Crear un backup

```bash
./backup_tracker.sh
```

El script:
1. Verifica conectividad (ping + SSH).
2. Limpia snapshots temporales abandonados.
3. Compara la carpeta local con el último snapshot.
4. Si no hay cambios, termina sin crear un nuevo snapshot.
5. Crea un snapshot incremental (`--delete`), lo renombra y rota los antiguos (máx. 5).

### Restaurar un snapshot

```bash
./restore.sh
```

Muestra una lista de snapshots disponibles. Para restaurar uno concreto:

```bash
./restore.sh 2026-09-18_12:00:00
```

Muestra los cambios (añadidos, modificados, eliminados) y pide confirmación antes de sobrescribir la carpeta local.

## Automatización

### systemd (servicio `oneshot`)

Copia `backup.service` a `/etc/systemd/system/`:

```bash
sudo cp backup.service /etc/systemd/system/
sudo systemctl daemon-reload
```

Los logs se consultan con:

```bash
journalctl -u backup.service
```

Nota: en sistemas con SELinux puede necesitar:

```bash
sudo setsebool -P rsync_client 1
sudo setsebool -P rsync_export_all_ro 1
```

### NetworkManager dispatcher

Copia `10-launch.sh` a `/etc/NetworkManager/dispatcher.d/`, de modo que el backup se ejecute automáticamente al conectarse la red:

```bash
sudo cp 10-launch.sh /etc/NetworkManager/dispatcher.d/
```

Deja solo la siguiente linea si lo usas como servicio de `systemd`.
```bash
+	systemctl start backup.service
-	# runuser -u hvidal -- /home/hvidal/datos_lin/programacion/scripts/backup_tracker/backup_tracker.sh
```


Cada snapshot es un directorio completo (gracias a los hard links); el consumo de disco extra es mínimo entre copias consecutivas.

## Notas

- Las carpetas `org/` y `backup/` están excluidas del control de versiones.
- El snapshot se crea primero en `<nombre>.tmp` y se renombra solo al finalizar, protegiendo la integridad ante cortes o errores.
