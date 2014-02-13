#!/bin/bash

# Note: RackSpace has hidden some of the images. Please see this page
# http://www.rackspace.com/knowledge_center/article/hidden-base-images

set -exu

THIS_DIR=$(dirname $(readlink -f $0))
BIN_DIR="$THIS_DIR/../bin"
SCRIPTS_DIR="$THIS_DIR/../scripts"
export PATH=$PATH:$BIN_DIR

SCRIPTS_TO_INSTALL="$SCRIPTS_DIR/*"
INSTALL_TARGET="/opt/nodepool-scripts/"
XENSERVER_PASSWORD=xspassword
STAGING_VM_URL="$1"
TEST_POSTFIX="$2"
TESTVM_NAME="Jxitct${TEST_POSTFIX}"
SNAPVM_NAME="Jxitcs${TEST_POSTFIX}"
IMAGE_NAME="Jxitci${TEST_POSTFIX}"

function main() {
    launch_vm $TESTVM_NAME "62df001e-87ee-407c-b042-6f4e13f5d7e1"
    start_install
    xitc-wait-until-done $VM_IP $PRIVKEY
    prepare_for_snapshot
    delete_all_images $IMAGE_NAME
    perform_snapshot $TESTVM_NAME $IMAGE_NAME
    launch_vm $SNAPVM_NAME $IMAGE_NAME
    xitc-wait-until-done $VM_IP $PRIVKEY
    test_ssh_access_to_dom0

    echo "ALL TESTS PASSED"
}

function wait_for_ssh() {
    while ! echo "kk" | nc -w 1 "$VM_IP" 22 > /dev/null 2>&1; do
            sleep 1
            echo -n "x"
    done
}

function launch_vm() {
    local vm_name
    local image_name

    vm_name="$1"
    image_name="$2"

    PRIVKEY="$vm_name.pem"
    privkey_name="$vm_name"

    rm -f "$PRIVKEY" || true
    nova keypair-delete "$privkey_name" || true
    nova delete "$vm_name" || true

    while nova list | grep -q "$vm_name"; do
        sleep 1
    done

    nova keypair-add "$privkey_name" > "$PRIVKEY"
    chmod 0600 "$PRIVKEY"

    nova boot \
        --poll \
	--image "$image_name" \
	--flavor "performance1-8" \
	"$vm_name" --key-name "$privkey_name"

    VM_IP=$(xitc-get-ip-address-of-instance $vm_name)

    set +x
    wait_for_ssh
    set -x
}

COMMON_SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp $COMMON_SSH_OPTIONS"
SSH="ssh -o BatchMode=yes $COMMON_SSH_OPTIONS"

function start_install() {
    $SSH -i $PRIVKEY root@$VM_IP mkdir -p "$INSTALL_TARGET"
    $SCP -i $PRIVKEY $SCRIPTS_TO_INSTALL "root@$VM_IP:$INSTALL_TARGET"
    $SSH -i $PRIVKEY root@$VM_IP bash "$INSTALL_TARGET/convert_node_to_xenserver.sh" "$XENSERVER_PASSWORD" "$STAGING_VM_URL" "Devstack"
}

function prepare_for_snapshot() {
    $SSH -i $PRIVKEY root@$VM_IP "rm -f $(xitc-print-stamp-path)"
    $SSH -i $PRIVKEY root@$VM_IP "sync && sleep 5"
}

function perform_snapshot() {
    local vm_name
    local snapshot_name

    vm_name="$1"
    snapshot_name="$2"

    nova image-create --poll "$vm_name" "$snapshot_name"
}

function delete_all_images() {
    local image_name

    nova image-list |
        grep $IMAGE_NAME |
        sed -e 's/|//g' -e 's/ \+/ /g' -e 's/^ *//g' |
        cut -d" " -f 1 |
        while read imageid; do
            nova image-delete $imageid
        done
}

function test_ssh_access_to_dom0() {
    local vm_ip
    local privkey_path

    vm_ip="$VM_IP"
    privkey_path="$PRIVKEY"

    $SSH -i $PRIVKEY root@$VM_IP bash << EOF
set -eux
sudo -u domzero ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.33.2 true
EOF
}

main
