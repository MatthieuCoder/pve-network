#!/bin/sh

set -e

while IFS= read -r dest; do
  cat frr.conf.local | sed -e "s/ID_ID/$dest/" | ssh "root@$dest" "cat > /etc/frr/frr.conf.local"
done <<< $(cat proxmox_hosts)
