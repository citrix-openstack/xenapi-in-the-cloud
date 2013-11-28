xenapi-in-the-cloud
===================

Tools to launch a XenAPI managed hypervisor in the cloud

## Start XenServer in the RackSpace cloud

To launch an instance, first make sure, that you have `nova` installed, and
that your environment has all the settings. For setting up your environment
and nova, please refer to [the official Rackspace documentation](http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/section_gs_install_nova.html).

After your environment is set up, you will need a public key to be injected
to the xenserver environment. I will use the `authorized_keys` file in my home
this time.

You also need to come up with a password that will be used for your XenServer.
In this case, I will use `xspassword`.

With all the parameters, the command should look like this:

   rs-xenserver.sh "xs62" "xspassword" "$(cat ~/.ssh/authorized_keys)"

Briefly, this script will:

 - Create a new keypair, launch an ubuntu PVHVM instance
 - SSH to the instance, download xenserver installer
 - Remaster the xenserver installer with an answerfile, ramdisk support
 - Add a grub menu entry - so installer boots next time
 - Reboot the machine - installer kicks off
 - Installer will reboot the machine
 - Script waits until the instance is accessible through ssh, and returns
