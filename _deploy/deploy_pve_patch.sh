#!/bin/sh

set -e

rm *.deb
cp ~/Documents/dev/frr-evpn-route-watcher/*.deb .
cp ../*.deb .
while IFS= read -r dest; do
  ssh -n "root@$dest" "rm pve-network-patch/*" || true
  scp *.deb "root@$dest:pve-network-patch/"
  ssh -n "root@$dest" "dpkg -i --force-overwrite --force-confmiss pve-network-patch/*.deb"
done <<< $(cat proxmox_hosts)
