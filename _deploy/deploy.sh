#!/bin/sh

set -e

rm *.deb
cp ../*.deb .
while IFS= read -r dest; do
  ssh -n "root@$dest" "rm pve-network-patch/*"
  scp *.deb "root@$dest:pve-network-patch/"
  ssh -n "root@$dest" "dpkg -i pve-network-patch/*.deb"
done < proxmox_hosts
