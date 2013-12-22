#!/bon/bash

set -eux

XENSERVER="192.168.33.2"

apt-get -qy update
apt-get install -qy shorewall dnsmasq

tee /etc/shorewall/interfaces << EOF
net eth1 detect dhcp,tcpflags,nosmurfs
lan eth2 detect dhcp
EOF

tee /etc/shorewall/zones << EOF
fw firewall
net ipv4
lan ipv4
EOF

tee /etc/shorewall/policy << EOF
lan net ACCEPT
lan fw ACCEPT
fw net ACCEPT
fw lan ACCEPT
net all DROP
all all REJECT info
EOF

tee /etc/shorewall/rules << EOF
ACCEPT net fw tcp 22
EOF


tee /etc/shorewall/masq << EOF
eth1 eth2
EOF

# Turn on IP forwarding
sed -i /etc/shorewall/shorewall.conf \
-e 's/IP_FORWARDING=.*/IP_FORWARDING=On/g'

# Enable shorewall on startup
sed -i /etc/default/shorewall \
-e 's/startup=.*/startup=1/g'

# Configure dnsmasq
tee -a /etc/dnsmasq.conf << EOF
interface=eth2
dhcp-range=192.168.33.50,192.168.33.150,12h
bind-interfaces
EOF

service shorewall start
service dnsmasq start

wget -qO devstack-installer.sh http://downloads.vmd.citrix.com/OpenStack/jenkins-xva-build-external-326.sh

ssh-keygen -t rsa -N "" -f devstack_key.priv

ssh-keyscan "$XENSERVER" >> ~/.ssh/known_hosts

bash devstack-installer.sh \
    "$XENSERVER" "$XENSERVER_PASSWORD" "devstack_key.priv" \
    -j http://downloads.vmd.citrix.com/OpenStack/external-precise.xva \
    -t smoke
