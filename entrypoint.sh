#!/bin/bash
set -e

VPN_SUBNET="${VPN_SUBNET:-10.10.10.0/24}"
VPN_DNS="${VPN_DNS:-1.1.1.1,8.8.8.8}"

CERT="/etc/swanctl/x509/server-cert.pem"
KEY="/etc/swanctl/private/server-key.pem"
VICI="/var/run/charon.vici"

if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    echo "[ERROR] Missing server certificate or private key"
    exit 1
fi

mkdir -p /etc/swanctl/conf.d
mkdir -p /var/run

echo "=== Configuring NAT & Forwarding ==="

EXT_IF=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$EXT_IF" ]; then
    echo "[ERROR] Cannot determine external interface"
    exit 1
fi

echo "External interface: $EXT_IF"

# 避免容器重启后重复添加规则
iptables -t nat -C POSTROUTING \
    -s "${VPN_SUBNET}" -o "${EXT_IF}" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING \
    -s "${VPN_SUBNET}" -o "${EXT_IF}" -j MASQUERADE

iptables -C FORWARD \
    -s "${VPN_SUBNET}" \
    -m conntrack \
    --ctstate NEW,RELATED,ESTABLISHED \
    -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD \
    -s "${VPN_SUBNET}" \
    -m conntrack \
    --ctstate NEW,RELATED,ESTABLISHED \
    -j ACCEPT

iptables -C FORWARD \
    -d "${VPN_SUBNET}" \
    -m conntrack \
    --ctstate RELATED,ESTABLISHED \
    -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD \
    -d "${VPN_SUBNET}" \
    -m conntrack \
    --ctstate RELATED,ESTABLISHED \
    -j ACCEPT

iptables -t mangle -C FORWARD \
    -p tcp --tcp-flags SYN,RST SYN \
    -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
    || iptables -t mangle -A FORWARD \
    -p tcp --tcp-flags SYN,RST SYN \
    -j TCPMSS --clamp-mss-to-pmtu


echo "=== Starting charon daemon ==="

# 清理旧 socket
rm -f "$VICI"

# 启动 charon
/usr/lib/ipsec/charon &
CHARON_PID=$!

echo "charon PID: $CHARON_PID"

# 等待 charon + VICI
echo "=== Waiting for charon.vici ==="

for i in $(seq 1 30); do

    # charon 已经退出
    if ! kill -0 "$CHARON_PID" 2>/dev/null; then
        echo "[ERROR] charon exited unexpectedly"

        echo "=== Process status ==="
        ps aux | grep '[c]haron' || true

        exit 1
    fi

    # socket 已生成
    if [ -S "$VICI" ]; then
        echo "charon.vici socket detected"

        # 真正测试 VICI 是否可以连接
        if swanctl --stats >/dev/null 2>&1; then
            echo "VICI connection is ready"
            break
        fi
    fi

    sleep 1
done

# 最后再确认一次
if ! swanctl --stats >/dev/null 2>&1; then
    echo "[ERROR] VICI socket exists but charon is not accepting connections"

    echo "=== charon process ==="
    ps aux | grep '[c]haron' || true

    exit 1
fi


echo "=== Loading swanctl credentials ==="
swanctl --load-creds


echo "=== Loading swanctl pools ==="
swanctl --load-pools


echo "=== Loading swanctl connections ==="
swanctl --load-conns


echo "=== Loaded connections ==="
swanctl --list-conns


echo "=== Loaded pools ==="
swanctl --list-pools


echo "=== strongSwan is ready ==="

wait "$CHARON_PID"

