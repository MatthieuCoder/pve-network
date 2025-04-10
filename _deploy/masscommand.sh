#!/bin/sh

set -e

while IFS= read -r dest; do
  echo "$dest"
  ssh -n "root@$dest" "vtysh -c 'sh bgp summary'"
done <<< $(cat proxmox_hosts)
