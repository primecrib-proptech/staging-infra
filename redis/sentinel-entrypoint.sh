#!/bin/sh

set -e

REDIS_PASSWORD=$(cat /run/secrets/redis_root_password)

cat > /data/sentinel.conf <<EOF
port 26379

bind 0.0.0.0
protected-mode yes

dir /data

sentinel resolve-hostnames yes
sentinel announce-hostnames yes

sentinel monitor mymaster redis-master 6379 2

sentinel auth-pass mymaster ${REDIS_PASSWORD}

sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1

requirepass ${REDIS_PASSWORD}
EOF

exec redis-server /data/sentinel.conf --sentinel
