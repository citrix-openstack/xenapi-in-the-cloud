#!/bin/bash

set -exu

SCRIPT_TO_INSTALL="xenapi-in-rs.sh"
INSTALL_TARGET="/opt/nodepool-scripts/xenserver_cloud.sh"

function main() {
    launch_vm testvm "Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)"
    start_install
    wait_till_done
    prepare_for_snapshot
    wait_till_snapshottable
    perform_snapshot testvm testimage
    launch_vm snapvm testimage
    wait_till_done
    nova image-delete testimage

    echo "ALL TESTS PASSED"
}

function wait_for_ssh() {
    set +x
    while ! echo "kk" | nc -w 1 "$VM_IP" 22 > /dev/null 2>&1; do
            sleep 1
            echo -n "."
    done
    set -x
}

function launch_vm() {
    local vm_name
    local image_name

    vm_name="$1"
    image_name="$2"

    PRIVKEY="$vm_name.pem"
    privkey_name="tempkey-$vm_name"

    rm -f "$PRIVKEY" || true
    nova keypair-delete "$privkey_name" || true
    nova delete "$vm_name" --poll || true

    if nova list | grep -q "$vm_name"; then
        echo "ERROR: An instance already exists with the name $vm_name"
        exit 1
    fi

    nova keypair-add "$privkey_name" > "$PRIVKEY"
    chmod 0600 "$PRIVKEY"

    nova boot \
        --poll \
	--image "$image_name" \
	--flavor "performance1-8" \
	"$vm_name" --key-name "$privkey_name"

    while ! nova list | grep "$vm_name" | grep -q ACTIVE; do
            sleep 5
    done

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
}

COMMON_SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp $COMMON_SSH_OPTIONS"
SSH="ssh -o BatchMode=yes $COMMON_SSH_OPTIONS"

function start_install() {
    $SSH -i $PRIVKEY root@$VM_IP mkdir -p $(dirname "$INSTALL_TARGET")
    $SCP -i $PRIVKEY $SCRIPT_TO_INSTALL "root@$VM_IP:$INSTALL_TARGET"
    $SSH -i $PRIVKEY root@$VM_IP bash "$INSTALL_TARGET" minvm
}

function wait_till_file_exists() {
    set +x
    local fname

    fname="$1"

    echo -n "Waiting for $fname"

    while true; do
        wait_for_ssh
        if $SSH -i $PRIVKEY root@$VM_IP test -e $fname; then
            break
        else
            echo -n "."
            sleep 10
        fi
    done
    echo "Found!"
    set -x
}

function wait_till_done() {
    wait_till_file_exists /root/done.stamp
}

function wait_till_snapshottable() {
    sleep 20
}

function prepare_for_snapshot() {
    # Copy over ssh key
    $SCP -i $PRIVKEY $PRIVKEY root@$VM_IP:key
    $SSH -i $PRIVKEY root@$VM_IP "chmod 0600 key"
    $SSH -i $PRIVKEY root@$VM_IP "$SSH -i key root@192.168.33.2" << EOF
# These instructions are executed on dom0
# Prepare the box for snapshotting
set -eux
halt -p
EOF
}

function perform_snapshot() {
    local vm_name
    local snapshot_name

    vm_name="$1"
    snapshot_name="$2"

    nova image-create --poll "$vm_name" "$snapshot_name"
}

main
