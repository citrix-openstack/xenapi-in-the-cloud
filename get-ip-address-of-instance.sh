#!/bin/bash
set -eu

vm_name="$1"

function wait_for_ssh() {
    while ! echo "kk" | nc -w 1 "$VM_IP" 22 > /dev/null 2>&1; do
            sleep 1
    done
}

vm_id=$(nova list | grep "$vm_name" | tr -d " " | cut -d "|" -f 2)

while true; do
    VM_IP=$(nova show $vm_id | grep accessIPv4 | tr -d " " | cut -d "|" -f 3)
    if [ -z "$VM_IP" ]; then
            sleep 1
    else
            break
    fi
done

wait_for_ssh
echo $VM_IP
