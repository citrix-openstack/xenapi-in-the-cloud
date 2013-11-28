#!/bin/bash
set -xu

VM_NAME="$1"
XENSERVER_PASSWORD="$2"
AUTHORIZED_KEYS="$3"

WORK_DIR=$(mktemp -d)
TEMPORARY_PRIVKEY="$WORK_DIR/tempkey.pem"
TEMPORARY_PRIVKEY_NAME="tempkey-$VM_NAME"

nova keypair-add "$TEMPORARY_PRIVKEY_NAME" > "$TEMPORARY_PRIVKEY"
chmod 0600 "$TEMPORARY_PRIVKEY"

nova boot \
	--image "Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)" \
	--flavor "performance1-8" \
	"$VM_NAME" --key-name "$TEMPORARY_PRIVKEY_NAME"

while ! nova list | grep "$VM_NAME" | grep -q ACTIVE; do
	sleep 5
done

VM_ID=$(nova list | grep "$VM_NAME" | tr -d " " | cut -d "|" -f 2)

while true; do
	VM_IP=$(nova show $VM_ID | grep accessIPv4 | tr -d " " | cut -d "|" -f 3)
	if [ -z "$VM_IP" ]; then
		sleep 1
	else
		break
	fi
done

# Wait till ssh comes up
while ! echo "kk" | nc -w 1 $VM_IP 22; do
	sleep 1
done

ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP bash -s -- << EXECUTE_IT_ON_VM
set -eux
apt-get -qy update
apt-get -qy install wget
wget -qO xs62.iso http://downloadns.citrix.com.edgesuite.net/akdlm/8159/XenServer-6.2.0-install-cd.iso
sed -ie 's/^GRUB_HIDDEN_TIMEOUT/#GRUB_HIDDEN_TIMEOUT/g' /etc/default/grub
sed -ie 's/^GRUB_HIDDEN_TIMEOUT_QUIET/#GRUB_HIDDEN_TIMEOUT_QUIET/g' /etc/default/grub
# sed -ie 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=-1/g' /etc/default/grub
sed -ie 's/^.*GRUB_TERMINAL=.*$/GRUB_TERMINAL=console/g' /etc/default/grub

ADDRESS=\$(grep -m 1 "address" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
NETMASK=\$(grep -m 1 "netmask" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
GATEWAY=\$(grep -m 1 "gateway" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
NAMESERVER_ELEMENTS=\$(cat /etc/resolv.conf | grep nameserver | cut -d " " -f 2 | sort | uniq | sed -e 's,^,<nameserver>,g' -e 's,$,</nameserver>,g')

# xsint will be searched
rm -rf /xsint
mkdir /xsinst
cp xs62.iso /xsinst/

mkdir -p /mnt/xs-iso
mount -o loop xs62.iso /mnt/xs-iso
mkdir /opt/xs-install

cp -r /mnt/xs-iso/* /opt/xs-install/
umount /mnt/xs-iso

## Remastering the initial root disk

rm -rf /opt/xs-install/install_modded.img
rm -rf /opt/xs-install/install-remaster/
mkdir -p /opt/xs-install/install-remaster/
(
cd /opt/xs-install/install-remaster/
zcat "/opt/xs-install/install.img" | cpio -idum --quiet
cat > answerfile.xml << EOF
<?xml version="1.0"?>
<installation srtype="ext">
<primary-disk>sda</primary-disk>
<keymap>us</keymap>
<root-password>$XENSERVER_PASSWORD</root-password>
<source type="url">file:///tmp/ramdisk</source>
<admin-interface name="eth0" proto="static">
<ip>\$ADDRESS</ip>
<subnet-mask>\$NETMASK</subnet-mask>
<gateway>\$GATEWAY</gateway>
</admin-interface>
\$NAMESERVER_ELEMENTS
<timezone>America/Los_Angeles</timezone>
<script stage="filesystem-populated" type="url">file:///postinst.sh</script>
</installation>
EOF

cat > postinst.sh << EOF
#!/bin/sh
touch \\\$1/tmp/postinst.sh.executed
cp /firstboot.sh \\\$1/etc/firstboot.d/95-firstboot
chmod 777 \\\$1/etc/firstboot.d/95-firstboot
sed -ie "s,PasswordAuthentication yes,PasswordAuthentication no,g" \\\$1/etc/ssh/sshd_config
echo "$AUTHORIZED_KEYS" > \\\$1/root/.ssh/authorized_keys
EOF

cat > firstboot.sh << EOF
#!/bin/bash
EOF

find . -print | cpio -o --quiet -H newc | xz --format=lzma > /opt/xs-install/install_modded.img
)

cat > /etc/grub.d/45_xs-install << EOF
cat << XS_INSTALL
menuentry 'XenServer installer' {
    multiboot /opt/xs-install/boot/xen.gz dom0_max_vcpus=1-2 dom0_mem=max:752M com1=115200,8n1 console=com1,vga
    module /opt/xs-install/boot/vmlinuz xencons=hvc console=tty0 console=hvc0 make-ramdisk=/dev/sda1 answerfile=file:///answerfile.xml install
    module /opt/xs-install/install_modded.img
}
XS_INSTALL
EOF

# answerfile=file:///answerfile.xml install 

chmod +x /etc/grub.d/45_xs-install

sed -ie 's/GRUB_DEFAULT=0/GRUB_DEFAULT=4/g' /etc/default/grub
update-grub
reboot
EXECUTE_IT_ON_VM

sleep 30

# Wait till ssh comes up
while ! echo "kk" | nc -w 1 $VM_IP 22; do
	sleep 1
done

echo "XenServer should come up here: $VM_IP"
