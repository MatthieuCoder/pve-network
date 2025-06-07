#!/bin/sh

while IFS= read -r dest; do
  ssh -n "root@$dest" "vtysh -c 'debug all'"
  ssh -n "root@$dest" "printf \"conf t \\n log file /var/log/frr/debug.log debugging \\n end \\n wr\" | vtysh"
done <<< $(cat proxmox_hosts)
