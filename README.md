# proxmox-backup-server image

Proxmox Backup Server as a container, installed from the **official Proxmox `.deb`
packages** (`pbs-no-subscription`, Debian trixie). Nothing is compiled here: the PBS
binaries are the ones Proxmox ships, verified by apt against the Proxmox archive key
(whose SHA-256 is checked at build time).

Published as `ghcr.io/nocrusltd/proxmox-backup-server:v<version>` (linux/amd64), with
SLSA provenance + SBOM attestations.

## Why not build from source

`ayufan/pve-backup-server-dockerfiles` builds PBS from source and stopped at v4.2.0
(May 2026). Using Proxmox's own packages gives the exact upstream release (same build the
PVE hosts' `proxmox-backup-client` comes from), a ~1 minute build instead of a long Rust
build, and the stock x86-64 baseline target (no AVX2 / x86-64-v3 requirement).

## Drop-in for `ayufan/proxmox-backup-server`

Same runtime layout: `ENTRYPOINT /runit/entrypoint.sh`, `CMD runsvdir /runit`
(api, proxy, cron services), volumes `/etc/proxmox-backup`, `/var/lib/proxmox-backup`,
`/var/log/proxmox-backup`, port 8007, `backup` uid/gid 34. `/run` must be a tmpfs.

One deliberate difference: **no default `admin@pbs` user with a well-known password** is
seeded into an empty `/etc/proxmox-backup`. On a fresh install create one first:

```bash
docker exec <ctr> proxmox-backup-manager user create admin@pbs --password '<pw>'
docker exec <ctr> proxmox-backup-manager acl update / Admin --auth-id admin@pbs
```

Existing config volumes are used as-is.

## Bumping the version

Change `ARG PBS_VERSION` in the `Dockerfile` to the new Debian version (check
`http://download.proxmox.com/debian/pbs/dists/trixie/pbs-no-subscription/binary-amd64/Packages.gz`)
and merge to `main`. CI builds, runs `scripts/smoke-test.sh` (GUI 200, API 401,
`proxmox-backup-manager versions` matches), then pushes `v<version without -N>`.
Pin consumers by digest.
