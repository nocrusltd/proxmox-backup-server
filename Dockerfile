# syntax=docker/dockerfile:1
#
# Proxmox Backup Server from the OFFICIAL Proxmox .deb packages (pbs-no-subscription,
# Debian trixie) - no source build. Runtime layout (runit services, entrypoint, volumes,
# config paths, port 8007) mirrors ayufan/proxmox-backup-server so it is a drop-in
# replacement for that image.
#
# debian:trixie (NOT -slim): slim's dpkg path-excludes drop /usr/share/doc, which is where
# proxmox-backup-docs puts the GUI's built-in documentation.
ARG DEBIAN_IMAGE=debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6
FROM ${DEBIAN_IMAGE}

# Exact package version installed (apt fails the build if it is not in the repo).
ARG PBS_VERSION=4.2.10-1

# Proxmox archive key for trixie. SHA-256 published in the PBS install docs:
# https://pbs.proxmox.com/docs/installation.html
ARG PROXMOX_KEYRING_SHA256=136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
COPY keys/proxmox-archive-keyring-trixie.gpg /usr/share/keyrings/proxmox-archive-keyring.gpg

RUN set -eux; \
    echo "${PROXMOX_KEYRING_SHA256}  /usr/share/keyrings/proxmox-archive-keyring.gpg" | sha256sum -c -; \
    printf '%s\n' \
      'Types: deb' \
      'URIs: http://download.proxmox.com/debian/pbs' \
      'Suites: trixie' \
      'Components: pbs-no-subscription' \
      'Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/proxmox.sources; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    # ssmtp satisfies the package's `postfix | mail-transport-agent` dependency without a
    # full MTA (same choice as the ayufan image); runit + cron supervise the daemons.
    apt-get install -y --no-install-recommends runit cron ssmtp ca-certificates; \
    apt-get install -y --no-install-recommends "proxmox-backup-server=${PBS_VERSION}"; \
    # openssh-server is a hard dependency but never started here; drop the host keys its
    # postinst generated so no private key is baked into the image.
    rm -f /etc/ssh/ssh_host_*; \
    # The package ships the pbs-enterprise apt source enabled. Without a subscription it
    # answers 401, so PBS's daily "aptupdate" task ends with a warning every day. Disable
    # it (what the GUI's Repositories panel does), then check the result rather than the
    # file's layout: apt must no longer plan to fetch from the enterprise repository and
    # must still plan to fetch pbs-no-subscription (--print-uris fetches nothing).
    echo 'Enabled: false' >> /etc/apt/sources.list.d/pbs-enterprise.sources; \
    uris="$(apt-get update --print-uris)"; \
    case "$uris" in *enterprise.proxmox.com*) echo 'pbs-enterprise source still enabled' >&2; exit 1 ;; esac; \
    case "$uris" in */debian/pbs/dists/trixie/pbs-no-subscription/*) ;; *) echo 'pbs-no-subscription source missing' >&2; exit 1 ;; esac; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    test "$(dpkg-query -W -f='${Version}' proxmox-backup-server)" = "${PBS_VERSION}"

COPY runit/ /runit/

VOLUME /etc/proxmox-backup
VOLUME /var/log/proxmox-backup
VOLUME /var/lib/proxmox-backup

EXPOSE 8007

ENTRYPOINT ["/runit/entrypoint.sh"]
CMD ["runsvdir", "/runit"]
