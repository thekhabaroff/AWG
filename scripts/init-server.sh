#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COMPOSE=(docker compose -f "$ROOT_DIR/compose.yaml" --project-directory "$ROOT_DIR")

usage() {
    echo "Usage: sudo $0 SERVER_IP_OR_DOMAIN [PORT] [PEER_NAME]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 3 ]] || usage
SERVER_ENDPOINT="$1"
ENV_PORT=""
if [[ -f "$ROOT_DIR/.env" ]]; then
    ENV_PORT="$(awk -F= '$1 == "SERVER_PORT" { gsub(/[[:space:]]/, "", $2); print $2 }' "$ROOT_DIR/.env" | tail -n 1)"
fi
SERVER_PORT="${2:-${ENV_PORT:-51820}}"
PEER_NAME="${3:-phone}"

if (( ${#SERVER_ENDPOINT} > 253 )) || [[ ! "$SERVER_ENDPOINT" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$ ]]; then
    echo "Use a public IPv4 address or DNS hostname (IPv6 literals are not supported by this setup)." >&2
    exit 2
fi

[[ "$SERVER_PORT" =~ ^[0-9]{1,5}$ ]] || usage
(( SERVER_PORT >= 1 && SERVER_PORT <= 65535 )) || usage
if [[ -n "$ENV_PORT" && "$SERVER_PORT" != "$ENV_PORT" ]]; then
    echo "The script port ($SERVER_PORT) must match SERVER_PORT ($ENV_PORT) in .env." >&2
    exit 2
fi
if [[ -z "$ENV_PORT" && "$SERVER_PORT" != "51820" ]]; then
    echo "For a non-default port, set SERVER_PORT=$SERVER_PORT in .env before initializing." >&2
    exit 2
fi
[[ "$PEER_NAME" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || {
    echo "Peer name may contain only letters, digits, underscore and hyphen (max 32)." >&2
    exit 2
}

CONFIG_DIR="$ROOT_DIR/config"
SERVER_CONFIG="$CONFIG_DIR/wg0.conf"
CLIENT_CONFIG="$CONFIG_DIR/${PEER_NAME}.conf"

if [[ $(id -u) -ne 0 ]]; then
    echo "Run this script with sudo so Docker can create the protected config files." >&2
    exit 1
fi

exec 9>"$ROOT_DIR/.init-server.lock"
if ! flock -n 9; then
    echo "Another initialization is already running." >&2
    exit 1
fi

if [[ -e "$SERVER_CONFIG" || -e "$CLIENT_CONFIG" ]]; then
    echo "Config already exists; refusing to overwrite keys or profiles in $CONFIG_DIR." >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"
umask 077

awg() {
    "${COMPOSE[@]}" run --rm --no-deps -T --entrypoint /usr/bin/awg awg "$@"
}

server_private="$(awg genkey)"
server_public="$(printf '%s\n' "$server_private" | awg pubkey)"
client_private="$(awg genkey)"
client_public="$(printf '%s\n' "$client_private" | awg pubkey)"
preshared_key="$(awg genpsk)"

SERVER_TMP="$(mktemp "$CONFIG_DIR/.wg0.conf.XXXXXX")"
CLIENT_TMP=""
COMMITTED=0
cleanup() {
    rm -f "$SERVER_TMP"
    [[ -z "$CLIENT_TMP" ]] || rm -f "$CLIENT_TMP"
    if [[ "$COMMITTED" != "1" ]]; then
        rm -f "$SERVER_CONFIG" "$CLIENT_CONFIG"
    fi
}
trap cleanup EXIT
CLIENT_TMP="$(mktemp "$CONFIG_DIR/.${PEER_NAME}.conf.XXXXXX")"

cat > "$SERVER_TMP" <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $server_private
MTU = 1280
Jc = 0
Jmin = 0
Jmax = 0
S1 = 0
S2 = 0
S3 = 0
S4 = 0
H1 = 5
H2 = 100000005
H3 = 200000005
H4 = 300000005
RandomTrailers = off
PostUp = iptables -A FORWARD -i %i -o eth0 -s 10.66.66.0/24 -j ACCEPT; iptables -A FORWARD -i eth0 -o %i -d 10.66.66.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o eth0 -s 10.66.66.0/24 -j ACCEPT; iptables -D FORWARD -i eth0 -o %i -d 10.66.66.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = 10.66.66.2/32
EOF

cat > "$CLIENT_TMP" <<EOF
[Interface]
PrivateKey = $client_private
Address = 10.66.66.2/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280
Jc = 0
Jmin = 0
Jmax = 0
S1 = 0
S2 = 0
S3 = 0
S4 = 0
H1 = 5
H2 = 100000005
H3 = 200000005
H4 = 300000005
RandomTrailers = off

[Peer]
PublicKey = $server_public
PresharedKey = $preshared_key
Endpoint = $SERVER_ENDPOINT:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 0600 "$SERVER_TMP" "$CLIENT_TMP"
mv "$SERVER_TMP" "$SERVER_CONFIG"
mv "$CLIENT_TMP" "$CLIENT_CONFIG"
COMMITTED=1
trap - EXIT

echo "Created protected server and client configs in $CONFIG_DIR."
echo "Client profile: $CLIENT_CONFIG"
echo "The client private key and preshared key are in that file; do not publish it."
