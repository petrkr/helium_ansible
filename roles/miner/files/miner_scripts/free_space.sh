#!/usr/bin/env bash

DATA_DIR="/home/pi/miner_data"
USED_PCT=$(df --output='pcent' -l / |awk '/^ ?[0-9]+\%/ {split($1,a,"%"); print a[1]}')
LIMIT=90

if [ "${USED_PCT}" -ge "${LIMIT}" ] ; then
        podman image prune -fa
        podman stop miner
        rm -rf ${DATA_DIR}/log ${DATA_DIR}/blockchain.db
        podman start miner
        sleep 5m
        /home/pi/miner_scripts/fastsync.sh
fi
