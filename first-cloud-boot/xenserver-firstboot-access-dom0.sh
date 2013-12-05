xe pif-introduce device=eth0 host-uuid=\$(xe host-list --minimal) mac=$MACADDRESS
xe pif-reconfigure-ip uuid=\$(xe pif-list device=eth0 --minimal) mode=static IP=$ADDRESS netmask=$NETMASK gateway=$GATEWAY DNS=$NAMESERVERS
xe host-management-reconfigure pif-uuid=\$(xe pif-list device=eth0 --minimal)
