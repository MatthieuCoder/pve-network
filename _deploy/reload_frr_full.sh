#!/bin/sh

set -e

while IFS= read -r dest; do
  ssh -n "root@$dest" "systemctl stop frr"
  echo "stopped frr on $dest"
  sleep 5
done <<< $(cat proxmox_hosts)

while IFS= read -r dest; do
  ssh -n "root@$dest" "systemctl start frr"
  echo "started frr on $dest"
  sleep 5
done <<< $(cat proxmox_hosts)
