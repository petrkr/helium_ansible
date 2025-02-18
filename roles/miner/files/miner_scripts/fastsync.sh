#!/usr/bin/env bash
MINER_HEIGHT=$(curl -d '{"jsonrpc":"2.0","id":"id","method":"block_height","params":[]}' -s -o - http://localhost:4467/ | jq .result.height)
SNAP_HEIGHT=$(curl -s https://helium-snapshots.nebracdn.com/latest.json | jq .height)
if [ "${MINER_HEIGHT}" -lt "${SNAP_HEIGHT}" ] ; then
        echo "Downloading snapshot ${SNAP_HEIGHT}"
        podman exec miner wget https://helium-snapshots.nebracdn.com/snap-${SNAP_HEIGHT} -O /var/data/snap/snap-${SNAP_HEIGHT}.scratch
        podman exec miner miner repair sync_pause
        podman exec miner miner repair sync_cancel
        podman exec miner mv /var/data/snap/snap-${SNAP_HEIGHT}.scratch /var/data/snap/snap-${SNAP_HEIGHT}
        podman exec miner miner snapshot load /var/data/snap/snap-${SNAP_HEIGHT}
        sleep 5
        podman exec miner miner repair sync_resume
else
        echo "Current miner height of ${MINER_HEIGHT} greater than the latest snapshot at ${SNAP_HEIGHT}"
        exit 1
fi
