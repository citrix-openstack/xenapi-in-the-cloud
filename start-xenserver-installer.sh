set -eux

wget -qO xs62.iso http://downloadns.citrix.com.edgesuite.net/akdlm/8159/XenServer-6.2.0-install-cd.iso
sed -ie 's/^GRUB_HIDDEN_TIMEOUT/#GRUB_HIDDEN_TIMEOUT/g' /etc/default/grub
sed -ie 's/^GRUB_HIDDEN_TIMEOUT_QUIET/#GRUB_HIDDEN_TIMEOUT_QUIET/g' /etc/default/grub
# sed -ie 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=-1/g' /etc/default/grub
sed -ie 's/^.*GRUB_TERMINAL=.*$/GRUB_TERMINAL=console/g' /etc/default/grub

ADDRESS=$(grep -m 1 "address" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
NETMASK=$(grep -m 1 "netmask" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
GATEWAY=$(grep -m 1 "gateway" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
NAMESERVER_ELEMENTS=$(cat /etc/resolv.conf | grep nameserver | cut -d " " -f 2 | sort | uniq | sed -e 's,^,<nameserver>,g' -e 's,$,</nameserver>,g')

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
<ip>$ADDRESS</ip>
<subnet-mask>$NETMASK</subnet-mask>
<gateway>$GATEWAY</gateway>
</admin-interface>
$NAMESERVER_ELEMENTS
<timezone>America/Los_Angeles</timezone>
<script stage="filesystem-populated" type="url">file:///postinst.sh</script>
</installation>
EOF

cat > postinst.sh << EOF
#!/bin/sh
touch \$1/tmp/postinst.sh.executed
cp /firstboot.sh \$1/etc/firstboot.d/95-firstboot
chmod 777 \$1/etc/firstboot.d/95-firstboot
sed -ie "s,PasswordAuthentication yes,PasswordAuthentication no,g" \$1/etc/ssh/sshd_config
echo "$AUTHORIZED_KEYS" > \$1/root/.ssh/authorized_keys
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

