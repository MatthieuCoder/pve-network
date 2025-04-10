#!/bin/sh

set -e

while IFS= read -r dest; do
  scp frr.conf.local "root@$dest:/etc/frr/frr.conf.local"
done <<< $(cat proxmox_hosts)
