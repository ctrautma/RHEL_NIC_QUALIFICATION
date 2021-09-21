#!/bin/bash

# There are 4 mdoules in this test suite: SR-IOV, OVS-Kernel, OVS-DPDK and Hardware offload (HWOL). Depending on which feature(s)
# you want to get the certification, please set the value as "true" below.

SRIOV_TEST=false
OVS_KERNEL_TEST=false
OVS_DPDK_TEST=false
HWOL_TEST=false

# Each module has sub-test module(s):
#   SR-IOV test module include throughput test
#   OVS-Kernel test module include ovs-perf, throughput and functional tests
#   OVS-DPDK test module has ovs-perf, throughput and functional tests
#   HWOL module has ovs-perf tests

# Device under test(DUT) is the system with the NIC to be certified
DUT=wsfd-advnetlab35.anl.lab.eng.bos.redhat.com

#TESTER is Trex in this case
TESTER=wsfd-advnetlab36.anl.lab.eng.bos.redhat.com
[[ -z "$ANSIBLE_CONTROLLER" ]] && [[ "$DUT" != "$(hostname)" ]] && [[ "$TESTER" != "$(hostname)" ]] && ANSIBLE_CONTROLLER="$(hostname)"

login_passwd=ROOT_PASSWORD

#nic speed Gb/s
nic_speed=25

# Guest image for ovs perf test
# download the lastest "KVM Guest Image" from https://access.redhat.com, then upload it to your local http server for DUT to download.
# While this doc is writting, the lastest version is rhel8.4 and the url is
# https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.4/x86_64/product-software
# Red Hat Enterprise Linux 8.4 Update KVM Guest Image 
guest_image=${guest_image:-http://netqe-infra01.knqe.lab.eng.bos.redhat.com/vm/rhel8.3.qcow2}

# IMAGE for throughput tests 
# Please download the compressed qcow2 image from below online storage then upload to your local http server for DUT to download.
# http://people.redhat.com/zfang/rhel8.3-vsperf-1Q-noviommu.qcow2.tar.lrz
# http://people.redhat.com/zfang/rhel8.3-vsperf-2Q-noviommu.qcow2.tar.lrz
# http://people.redhat.com/zfang/rhel8.3-vsperf-1Q-viommu.qcow2.tar.lrz
# http://people.redhat.com/zfang/rhel8.3-vsperf-2Q-viommu.qcow2.tar.lrz

ONE_QUEUE_IMAGE="http://netqe-bj.usersys.redhat.com/share/tli/vsperf_img/rhel7.6-vsperf-1Q-viommu.qcow2"
TWO_QUEUE_IMAGE="http://netqe-bj.usersys.redhat.com/share/tli/vsperf_img/rhel7.6-vsperf-2Q-viommu.qcow2"


qe_subscription_command=${qe_subscription_command-"subscription-manager register --serverurl=subscription.rhsm.stage.redhat.com:443/subscription --baseurl=https://cdn.re"}
trex_url=${trex_url:-"https://trex-tgn.cisco.com/trex/release/v2.82.tar.gz"}
trex_interface_1=ens1f0
trex_interface_2=ens1f1

#rpm paths should be http url type
ovs_rpm_path="http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch2.15/2.15.0/38.el8fdp/x86_64/openvswitch2.15-2.15.0-38.el8fdp.x86_64.rpm"
ovs_selinux_rpm_path="https://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch-selinux-extra-policy/1.0/28.el8fdp/noarch/openvswitch-selinux-extra-policy-1.0-28.el8fdp.noarch.rpm"
dpdk_rpm_path="http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/19.11/4.el8fdb.1/x86_64/dpdk-19.11-4.el8fdb.1.x86_64.rpm"
dpdk_tools_rpm_path=$"http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/19.11/4.el8fdb.1/x86_64/dpdk-tools-19.11-4.el8fdb.1.x86_64.rpm"

dut_interface_1=ens1f0
dut_interface_2=ens1f1
pf_representor=ens1f0
vf_representor=eth0
dut_interface_1_pciid=0000:3b:00.0
dut_interface_1_pciid=0000:3b:00.1
rhel_guest_image_path="/root/rhel8.3.qcow2"

rh_nic_cert=${rh_nic_cert:-"https://github.com/ctrautma/RHEL_NIC_QUALIFICATION/raw/master/rh_nic_cert.tar"}
#rh_nic_cert=${rh_nic_cert:-"http://netqe-bj.usersys.redhat.com/share/qding/CX-6/rh_nic_cert.tar"}
QE_SKIP_OVS_BOND_TEST=${QE_SKIP_OVS_BOND_TEST:-"yes"}

pkg_netperf=${pkg_netperf:-"http://netqe-bj.usersys.redhat.com/share/tools/netperf-20160222.tar.bz2"}
# iperf3 cannot be used in test because multicast support is required
# please see the info in https://iperf.fr/iperf-doc.php
iperf_rpm_path=${iperf_rpm_path:-"https://iperf.fr/download/fedora/iperf-2.0.8-2.fc23.x86_64.rpm"}


# For example, when dpdk rpm is dpdk-18.11.2-1.el7.x86_64.rpm , DPDK_VER is 1811-2, it must be in this format.
DPDK_VER="1811-2"
DPDK_URL="http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/18.11.2/1.el7/x86_64/dpdk-18.11.2-1.el7.x86_64.rpm"
DPDK_TOOL_URL="http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/18.11.2/1.el7/x86_64/dpdk-tools-18.11.2-1.el7.x86_64.rpm"
#NOTICE:Both client and server must have same trex verion .
TREX_URL="https://trex-tgn.cisco.com/trex/release/v2.82.tar.gz"


#config end 
################################################################################
