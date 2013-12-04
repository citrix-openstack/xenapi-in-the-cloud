#!/bin/bash
set -eux

export DEBIAN_FRONTEND=noninteractive

sudo tee /etc/shorewall/interfaces << EOF
net      eth1           detect          dhcp,tcpflags,nosmurfs
lan      eth2           detect          dhcp
EOF

sudo tee /etc/shorewall/zones << EOF
fw      firewall
net     ipv4
lan     ipv4
EOF

sudo tee /etc/shorewall/policy << EOF
lan             net             ACCEPT
lan             fw              ACCEPT
fw              net             ACCEPT
fw              lan             ACCEPT
net             all             DROP
all             all             REJECT          info
EOF

sudo tee /etc/shorewall/rules << EOF
ACCEPT  net                     fw      tcp     22
EOF


sudo tee /etc/shorewall/masq << EOF
eth1 eth2
EOF

# Turn on IP forwarding
sudo sed -i /etc/shorewall/shorewall.conf \
    -e 's/IP_FORWARDING=.*/IP_FORWARDING=On/g'

# Enable shorewall on startup
sudo sed -i /etc/default/shorewall \
    -e 's/startup=.*/startup=1/g'

# Configure dnsmasq
sudo tee -a /etc/dnsmasq.conf << EOF
interface=eth2
dhcp-range=192.168.33.50,192.168.33.150,12h
bind-interfaces
EOF

sudo service shorewall start
sudo service dnsmasq start
