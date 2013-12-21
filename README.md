xenapi-in-the-cloud
===================

Tools to run a XenAPI managed hypervisor in the cloud

## Start XenServer in the Rackspace cloud

To launch an instance, first make sure, that you have `nova` installed, and
that your environment has all the settings. For setting up your environment
and nova, please refer to [the official Rackspace documentation](http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/section_gs_install_nova.html).

To launch a XenServer in the Rackspace cloud:

    ./rs-xenserver.sh "xs62"

The name of the instance will be `xs62`, and a minimal precise VM will be
listening on the public IP address. The XenServer will be accessible on the IP
address: `192.168.33.2`. The password for the XenServer is `xspassword`.

## How Does it Work?

The idea is to have a single script (to make it easy to deploy), that is able
to convert an instance to a XenServer. Look at the [xenapi-in-rs.sh](xenapi-in-rs.sh)
file, and scroll to the end. There you will find the implementation of the
state machine.
