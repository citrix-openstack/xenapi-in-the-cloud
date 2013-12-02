#!/bon/bash

set -eux

XENSERVER="192.168.33.2"

sudo apt-get -qy update
sudo apt-get -qy install wget sshpass

wget -qO devstack-installer.sh http://downloads.vmd.citrix.com/OpenStack/jenkins-xva-build-external-326.sh

ssh-keygen -t rsa -N "" -f devstack_key.priv

ssh-keyscan "$XENSERVER" >> ~/.ssh/known_hosts

bash devstack-installer.sh \
    "$XENSERVER" "$XENSERVER_PASSWORD" "devstack_key.priv" \
    -j http://downloads.vmd.citrix.com/OpenStack/external-precise.xva \
    -t smoke
