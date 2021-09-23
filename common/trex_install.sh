#!/bin/bash

sshpass -p "$login_passwd" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@${TESTER}
# temparory workaround for fail to install python3_devel in trex_setup.yml
if [[ -n "$rpm_python3_devel" ]]
then
	ssh root@$TESTER "yum -y install $rpm_python3_devel"
fi
# run ansible play book to install trex
pushd ~/RHEL_NIC_QUALIFICATION/common
ansible-playbook trex_setup.yml
popd
