#!/bin/sh
set -eu

# Allow using the image for one-off awg commands, for example key generation.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

CONFIG=/etc/amnezia/amneziawg/wg0.conf
if [ ! -r "$CONFIG" ]; then
    echo "Missing readable config: $CONFIG" >&2
    exit 1
fi

# awg-quick tries the host kernel interface first. If it is unavailable, it
# falls back to the bundled amneziawg-go userspace implementation.
/usr/bin/awg-quick up wg0

stop_awg() {
    trap - TERM INT
    /usr/bin/awg-quick down wg0 || true
    exit 0
}

trap stop_awg TERM INT
while :; do
    sleep 86400 &
    wait "$!" || true
done
