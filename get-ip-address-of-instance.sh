#!/bin/bash
set -eu

vm_name="$1"

vm_id=$(nova list | grep "$vm_name" | tr -d " " | cut -d "|" -f 2)

while true; do
    VM_IP=$(nova show $vm_id | grep accessIPv4 | tr -d " " | cut -d "|" -f 3)
    if [ -z "$VM_IP" ]; then
            sleep 1
    else
            break
    fi
done

echo $VM_IP
