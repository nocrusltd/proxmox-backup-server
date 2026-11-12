#!/bin/bash
# libsystemd callers (e.g. proxmox-daily-update) expect the journald socket; there is no
# journald in the container, so point it at /dev/log.
mkdir -p /run/systemd/journal
if [[ ! -e /run/systemd/journal/socket ]]; then
  ln -s /dev/log /run/systemd/journal/socket
fi

exec "$@"
