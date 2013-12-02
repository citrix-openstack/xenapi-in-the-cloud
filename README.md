xenapi-in-the-cloud
===================

Tools to launch a XenAPI managed hypervisor in the cloud

## Start XenServer in the Rackspace cloud

To launch an instance, first make sure, that you have `nova` installed, and
that your environment has all the settings. For setting up your environment
and nova, please refer to [the official Rackspace documentation](http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/section_gs_install_nova.html).

You will need to come up with a password that will be used for your XenServer.
In this case, I will use `xspassword`.

With all the parameters, the command should look like this:

    ./rs-devstack-xenserver.sh "xs62" "xspassword"

Briefly, this script will:

 - Generate a keypair to access your final server
 - Create a temporary keypair for OS, launch an ubuntu PVHVM instance
 - execute [start-xenserver-installer.sh](start-xenserver-installer.sh) on the Ubuntu VM
    - Remaster the xenserver installer with an answerfile, ramdisk support
    - Add a grub menu entry - so installer boots next time
    - Reboot the machine - installer kicks off
    - Installer will reboot the machine again - next time, a XenServer's Dom0 will be accessible there.
 - wait for ssh
 - execute [replace-dom0-with-a-vm.sh](replace-dom0-with-a-vm.sh) on Dom0
 - wait 5 secs
 - execute [setup-routing.sh](setup-routing.sh) on DomU
    - It sets up the domU as a home router (dhcp server, dns proxy)
 - execute [start-devstack.sh](start-devstack.sh) on DomU
    - It will download a devstack installer script, and execute it, running smoke tests
