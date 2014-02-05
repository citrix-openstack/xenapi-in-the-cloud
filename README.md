# xenapi-in-the-cloud

[![Build Status](http://downloads.vmd.citrix.com/OpenStack/build-statuses/xenapi-in-the-cloud.png?someparam)]()

Tools to run a XenAPI managed hypervisor in the cloud

## Start XenServer in the Rackspace cloud

To launch a XenServer in the Rackspace cloud, launch an instance with the
following parameters:

 - flavor: `performance1-8`
 - image:  `62df001e-87ee-407c-b042-6f4e13f5d7e1`

[Documentation, on why the image needs to be specified with a uuid.](http://www.rackspace.com/knowledge_center/article/hidden-base-images)

Like this:

    nova boot \
        --poll \
        --image "62df001e-87ee-407c-b042-6f4e13f5d7e1" \
        --flavor "performance1-8" \
        --key-name matekey instance

After it's done, get the IP address of your instance. Some convenience scripts
can be found in the `bin` directory to do this, so set your `PATH` to include
the bin directory.

    IP=$(xitc-get-ip-address-of-instance instance)

Set up an environment variable to hold your ssh parameters (my private key is
stored in the file `matekey.pem`):

    SSH_PARAMS="-i matekey.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

Make a directory to hold the scripts:

    ssh \
        $SSH_PARAMS \
        root@$IP mkdir -p /opt/xenapi-in-the-cloud

Copy the files from the `scripts/` directory to that directory:

    scp \
        $SSH_PARAMS \
        scripts/* root@$IP:/opt/xenapi-in-the-cloud/

And execute that script with the following parameters:

    ssh \
        $SSH_PARAMS \
        root@$IP bash /opt/xenapi-in-the-cloud/convert_node_to_xenserver.sh \
            $XENSERVER_PASSWORD $APPLIANCE_URL $APPLIANCE_NAME_LABEL

Where:
 - `XENSERVER_PASSWORD` will be your XenServer's password.
 - `APPLIANCE_URL` is an url, specifying an XVA file, that will be configured
   to listen on the public IP. The appliance could be created with the help of
   [these scripts](https://github.com/citrix-openstack/openstack-xenapi-testing-xva)
 - `APPLIANCE_NAME_LABEL` is the name-label to be given to the appliance.

Now, you have to monitor the public IP with ssh, and look for a stamp file. To
get the name of the stamp file, execute `xitc-print-stamp-path`. Whenever you
successfully logged in, and the file exists, the transformation finished. A
helper script is provided, that will block until the stamp file has been found:

    xitc-wait-until-done $IP matekey.priv

XenServer will be accessible on the IP address: `192.168.33.2`.

## Testing

Make sure, that you have `nova` installed, and that your environment has all
the settings. For setting up your environment and nova, please refer to
[the official Rackspace documentation](http://docs.rackspace.com/servers/api/v2/cs-gettingstarted/content/section_gs_install_nova.html).

After these steps, run:

    test-rs.sh $STAGING_VM_URL $VM_POSTFIX

Investigate the return code and its output. `0` return code indicates that the
setup script works, and the instance could be used in a cloud environment.

## How Does it Work?

Look at the [convert_node_to_xenserver.sh](convert_node_to_xenserver.sh) file,
the main function implements a state machine, that's executed by both Ubuntu
and XenServer's dom0.
