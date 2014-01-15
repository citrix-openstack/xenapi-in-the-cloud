#!/bin/bash
set -eux

INSTANCE_NAME="imgupdate"
SNAPSHOT_NAME="xssnap"
XENSERVER_PASSWORD="password"
APPLIANCE_URL="http://downloads.vmd.citrix.com/OpenStack/xenapi-in-the-cloud-appliances/master.xva"
KEY_NAME=matekey
KEY_FILE=matekey.pem

nova delete "$INSTANCE_NAME" || true
nova image-delete "$SNAPSHOT_NAME" || true

nova boot \
    --poll \
    --image "62df001e-87ee-407c-b042-6f4e13f5d7e1" \
    --flavor "performance1-8" \
    --key-name $KEY_NAME $INSTANCE_NAME

IP=$(./get-ip-address-of-instance.sh $INSTANCE_NAME)

SSH_PARAMS="-i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

ssh \
    $SSH_PARAMS \
    root@$IP mkdir -p /opt/xenapi-in-the-cloud

scp \
    $SSH_PARAMS \
    xenapi-in-rs.sh root@$IP:/opt/xenapi-in-the-cloud/

ssh \
    $SSH_PARAMS \
    root@$IP bash /opt/xenapi-in-the-cloud/xenapi-in-rs.sh $XENSERVER_PASSWORD $APPLIANCE_URL

./wait-until-done.sh $IP $KEY_FILE

ssh \
    $SSH_PARAMS \
    -o ProxyCommand="ssh $SSH_PARAMS root@$IP nc %h %p -w 10 2> /dev/null" \
    root@192.168.33.2 "rm -f /root/done.stamp && halt -p"

sleep 30

nova image-create --poll "$INSTANCE_NAME" "$SNAPSHOT_NAME"
