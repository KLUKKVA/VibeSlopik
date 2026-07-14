ARG DEBIAN_SUITE=bookworm
FROM debian:${DEBIAN_SUITE}

ENV container=docker
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl iproute2 systemd systemd-sysv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask \
        dev-hugepages.mount \
        sys-fs-fuse-connections.mount \
        systemd-remount-fs.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
