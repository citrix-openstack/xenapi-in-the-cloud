xenapi-in-the-cloud
===================

Tools to run a XenAPI managed hypervisor in the cloud

## Start XenServer in the Rackspace cloud

To launch a XenServer in the Rackspace cloud, launch an instance with the
following parameters:

 - flavor: `performance1-8`
 - image:  `Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)`

Like this:

    nova boot \
        --poll \
        --image "Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)" \
        --flavor "performance1-8" \
        --key-name matekey instance

Copy the `xenapi-in-rs.sh` script to `/root/`:

    scp xenapi-in-rs.sh root@instance:/root/xenapi-in-rs.sh

And execute that script:

    ssh root@instance bash /root/xenapi-in-rs.sh minvm

Now, you have to monitor the public IP with ssh, and look for a stamp file:
`/root/done.stamp`. Whenever you successfully logged in, and the file exists,
the transformation finished:

    ./wait_until_done.sh instance matekey.priv

A minimal precise VM will be listening on the public IP address. The XenServer
will be accessible on the IP address: `192.168.33.2`. The password for the
XenServer is `xspassword`.

Halt the instance before you snapshot it.

## Testing

Make sure, that you have `nova` installed, and that your environment has all
the settings. For setting up your environment and nova, please refer to
[the official Rackspace documentation](http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/section_gs_install_nova.html).

After these steps, run:

    ./test-rs.sh

Investigate the return code and its output. `0` return code indicates that the
setup script works, and the instance could be used in a cloud environment,
assuming proper use (halt before snapshot)

## How Does it Work?

The idea is to have a single script (to make it easy to deploy), that is able
to convert an instance to a XenServer. Look at the [xenapi-in-rs.sh](xenapi-in-rs.sh)
file, and scroll to the end. There you will find the implementation of the
state machine.
