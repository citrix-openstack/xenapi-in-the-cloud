#!/bin/bash
set -eux

THIS_FILE="/root/xenserver-upstart.sh"
STATE_FILE="${THIS_FILE}.state"

function set_state() {
    local state

    state="$1"

    echo "$state" > $STATE_FILE
}

function get_state() {
    if [ -e "$STATE_FILE" ]; then
        cat $STATE_FILE
    else
        echo "START"
    fi
}

function create_resizing_initramfs_config() {
    cat > /usr/share/initramfs-tools/hooks/resize << EOF
#!/bin/sh

set -e

PREREQ=""

prereqs () {
	echo "\${PREREQ}"
}

case "\${1}" in
	prereqs)
		prereqs
		exit 0
		;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/resize2fs
copy_exec /sbin/e2fsck
copy_exec /usr/bin/expr
copy_exec /sbin/tune2fs
copy_exec /bin/grep
copy_exec /usr/bin/tr
copy_exec /usr/bin/cut
copy_exec /sbin/sfdisk
copy_exec /sbin/partprobe
copy_exec /bin/sed
EOF
    chmod +x /usr/share/initramfs-tools/hooks/resize

    cat > /usr/share/initramfs-tools/scripts/local-premount/resize << EOF
#!/bin/sh -e

PREREQ=""

# Output pre-requisites
prereqs()
{
        echo "\$PREREQ"
}

case "\$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /scripts/functions

log_begin_msg "Resize started"
touch /etc/mtab

tune2fs -O ^has_journal /dev/xvda1
e2fsck -fp /dev/xvda1
resize2fs /dev/xvda1 4G

# Number of 4k blocks
NUMBER_OF_BLOCKS=\$(tune2fs -l /dev/xvda1 | grep "Block count" | tr -d " " | cut -d":" -f 2)

# Convert them to 512 byte sectors
SIZE_OF_PARTITION=\$(expr \$NUMBER_OF_BLOCKS \\* 8)

# Sleep - otherwise sfdisk complains "BLKRRPART: Device or resource busy"
sleep 2

sfdisk -d /dev/xvda | sed -e "s,[0-9]\{8\},\$SIZE_OF_PARTITION,g" | sfdisk /dev/xvda
partprobe /dev/xvda
tune2fs -j /dev/xvda1

sync

log_end_msg "Resize finished"

EOF
    chmod +x /usr/share/initramfs-tools/scripts/local-premount/resize
}


function delete_resizing_initramfs_config() {
    rm -f /usr/share/initramfs-tools/hooks/resize
    rm -f /usr/share/initramfs-tools/scripts/local-premount/resize
}

function update_initramfs() {
    update-initramfs -u
}

function create_upstart_config() {
    cat > /etc/init/xenserver.conf << EOF
start on stopped rc RUNLEVEL=[2345]

task

script
    /bin/bash $THIS_FILE
    reboot
end script
EOF
}

function create_done_file() {
    touch /root/done.stamp
}

function download_xenserver_files() {
    wget -qO /root/xenserver.iso \
        http://downloadns.citrix.com.edgesuite.net/akdlm/8159/XenServer-6.2.0-install-cd.iso
}

function download_minvm_xva() {
    wget -qO /root/staging_vm.xva \
        http://downloads.vmd.citrix.com/OpenStack/minvm-dev.xva
}

function print_answerfile() {
    local repository
    local postinst
    local xenserver_pass

    repository="$1"
    postinst="$2"
    xenserver_pass="$3"

    cat << EOF
<?xml version="1.0"?>
<installation srtype="ext">
<primary-disk preserve-first-partition="true">sda</primary-disk>
<keymap>us</keymap>
<root-password>$xenserver_pass</root-password>
<source type="url">$repository</source>
<admin-interface name="eth0" proto="static">
<ip>192.168.34.2</ip>
<subnet-mask>255.255.255.0</subnet-mask>
<gateway>192.168.34.1</gateway>
</admin-interface>
<timezone>America/Los_Angeles</timezone>
<script stage="filesystem-populated" type="url">$postinst</script>
</installation>
EOF
}

function print_postinst_file() {
    local rclocal
    rclocal="$1"

    cat << EOF
#!/bin/sh
touch \$1/tmp/postinst.sh.executed
cp \$1/etc/rc.d/rc.local \$1/etc/rc.d/rc.local.backup
cat $rclocal > /etc/rc.d/rc.local
EOF
}

function print_rclocal() {
    cat << EOF
# This is the contents of the rc.local file on XenServer
mkdir -p /mnt/ubuntu
mount /dev/sda1 /mnt/ubuntu
ln -s /mnt/ubuntu${THIS_FILE} $THIS_FILE
ln -s /mnt/ubuntu${STATE_FILE} $STATE_FILE
if /bin/bash $THIS_FILE; then
    reboot
done
EOF
}

function create_ramdisk_contents() {
    mkdir /xsinst
    ln /root/xenserver.iso /xsinst/xenserver.iso
    print_rclocal > /xsinst/rclocal
    print_postinst_file "/tmp/ramdisk/rclocal" > /xsinst/postinst.sh
    print_answerfile \
        "file:///tmp/ramdisk" \
        "file:///tmp/ramdisk/postinst.sh" \
        "xspassword" > /xsinst/answerfile.xml
}

function extract_xs_installer() {
    local isofile
    local targetpath

    isofile="$1"
    targetpath="$2"

    local mountdir

    mountdir=$(mktemp -d)
    mount -o loop $isofile $mountdir
    mkdir -p $targetpath
    cp \
        $mountdir/install.img \
        $mountdir/boot/xen.gz \
        $mountdir/boot/vmlinuz \
        $targetpath
    umount $mountdir
}

function generate_xs_installer_grub_config() {
    local bootfiles
    local answerfile

    bootfiles="$1"
    answerfile="$2"

    cat > /etc/grub.d/45_xs-install << EOF
cat << XS_INSTALL
menuentry 'XenServer installer' {
    multiboot $bootfiles/xen.gz dom0_max_vcpus=1-2 dom0_mem=max:752M com1=115200,8n1 console=com1,vga
    module $bootfiles/vmlinuz xencons=hvc console=tty0 console=hvc0 make-ramdisk=/dev/sda1 answerfile=$answerfile install
    module $bootfiles/install.img
}
XS_INSTALL
EOF
    chmod +x /etc/grub.d/45_xs-install
}

function configure_grub() {
    sed -ie 's/^GRUB_HIDDEN_TIMEOUT/#GRUB_HIDDEN_TIMEOUT/g' /etc/default/grub
    sed -ie 's/^GRUB_HIDDEN_TIMEOUT_QUIET/#GRUB_HIDDEN_TIMEOUT_QUIET/g' /etc/default/grub
    # sed -ie 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=-1/g' /etc/default/grub
    sed -ie 's/^.*GRUB_TERMINAL=.*$/GRUB_TERMINAL=console/g' /etc/default/grub
    sed -ie 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/g' /etc/default/grub
}

function update_grub() {
    update-grub
}

function set_xenserver_installer_as_nextboot() {
    grub-set-default "XenServer installer"
}

case "$(get_state)" in
    "START")
        create_upstart_config
        create_resizing_initramfs_config
        update_initramfs
        delete_resizing_initramfs_config
        set_state "RESIZED"
        reboot
        ;;
    "RESIZED")
        download_xenserver_files
        download_minvm_xva
        create_ramdisk_contents
        extract_xs_installer /root/xenserver.iso /opt/xs-install
        generate_xs_installer_grub_config /opt/xs-install file:///tmp/ramdisk/answerfile.xml
        configure_grub
        update_grub
        set_xenserver_installer_as_nextboot
        set_state "XENSERVER"
        ;;
    "XENSERVER")
        create_done_file
        exit 1
        ;;
esac
