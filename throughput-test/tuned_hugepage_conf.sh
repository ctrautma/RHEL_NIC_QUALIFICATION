#!/bin/bash

cp /root/test_env.sh /root/RHEL_NIC_QUALIFICATION/throughput-test/
pushd /root/RHEL_NIC_QUALIFICATION/throughput-test

. Perf-Verify.conf
. test_env.sh

yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm git wget python3 hwloc hwloc-gui grubby tuned-profiles-cpu-partitioning
alternatives --set python /usr/bin/python3
pip3 install lxml
yum -y install $ovs_rpm_path $ovs_selinux_rpm_path $dpdk_rpm_path $dpdk_tools_rpm_path
git clone -b feature-cert --single-branch https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
yum install -y ~/RHEL_NIC_QUALIFICATION/throughput-test/lrzip-0.616-5.el7.x86_64.rpm
grubby --args='intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32' --update-kernel=$(grubby --default-kernel)
echo "isolated_cores=$PMD_CPU_1,$PMD_CPU_2,$PMD_CPU_3,$PMD_CPU_4,$VCPU1,$VCPU2,$VCPU3,$VCPU4,$VCPU5" >> /etc/tuned/cpu-partitioning-variables.conf
tuned-adm profile cpu-partitioning
systemctl enable tuned

