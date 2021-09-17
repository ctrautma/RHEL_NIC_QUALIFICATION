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

login_passwd=100yard-

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
ovs_rpm_path="http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch2.13/2.13.0/18.el8fdp/x86_64/openvswitch2.13-2.13.0-18.el8fdp.x86_64.rpm"
ovs_selinux_rpm_path="http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch-selinux-extra-policy/1.0/23.el8fdp/noarch/openvswitch-selinux-extra-policy"
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




# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Run Throughput tests
#   Author: Christian Trautman <ctrautma@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#######################################################################
# NIC Device names such as p6p1 p6p2
NIC1=$dut_interface_1
NIC2=$dut_interface_2

# PMD CPUS 
# Example with a layout such as seen from the output cpu_layout.py
# python cpu_layout.py
# ======================================================================
# Core and Socket Information (as reported by '/sys/devices/system/cpu')
# ======================================================================
#
# cores =  [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13]
# sockets =  [0, 1]
#
#         Socket 0        Socket 1
#         --------        --------
# Core 0  [0, 24]         [1, 25]
# Core 1  [2, 26]         [3, 27]
# Core 2  [4, 28]         [5, 29]
# Core 3  [6, 30]         [7, 31]
# Core 4  [8, 32]         [9, 33]
# Core 5  [10, 34]        [11, 35]
# Core 8  [12, 36]        [13, 37]
# Core 9  [14, 38]        [15, 39]
# Core 10 [16, 40]        [17, 41]
# Core 11 [18, 42]        [19, 43]
# Core 12 [20, 44]        [21, 45]
# Core 13 [22, 46]        [23, 47]

# To user 44,20 ,if your NIC is on Numa 0 you would use PMD_CPU_1=44 PMD_CPU2=20
# To use cores 44,20 and 42,18 I would use  PMD_CPU_1=44 PMD_CPU2=20 PMD_CPU3=42 PMD_CPU4=18

PMD_CPU_1=${sorted_nicnumanode_cpu_list[0]}
PMD_CPU_2=$(sibling ${sorted_nicnumanode_cpu_list[0]})
PMD_CPU_3=${sorted_nicnumanode_cpu_list[1]}
PMD_CPU_4=$(sibling ${sorted_nicnumanode_cpu_list[1]})

# Virtual NIC Guest CPU Binding
# Using the same scripts above assign first VCPU to a single core. Then assign
# VCPU2 and VCPU3 to a core/HT pair such as 4,28. Should not be a core already
# in use by the PMD MASK. All CPU assignments should be on different
# Hyperthreads.

VCPU1=$(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-1]})
VCPU2=${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-1]}
VCPU3=$(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-2]})

# Will need additional VCPUs for 2 queue test 
VCPU4=$(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-3]})
VCPU5=${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-3]}


# TESTPMD descriptor size, can be used to modify descriptor sizes inside of VM when running TESTPMD for dpdk and kernel
# Throughput tests. SR-IOV options can be used to modify sr-iov descriptor sizes
TXD_SIZE=512
RXD_SIZE=512
SRIOV_TXD_SIZE=2048
SRIOV_RXD_SIZE=2048

# Update your Trex trafficgen info below
TRAFFICGEN_TREX_HOST_IP_ADDR=$TESTER

# Mac addresses of the ports configured in TRex Server
TRAFFICGEN_TREX_PORT1=$trex_interface_1
TRAFFICGEN_TREX_PORT2=$trex_interface_2

#SR-IOV Information
# To run SR-IOV tests please complete the following info
# NIC Device name for VF on NIC1 and NIC2 Example p6p1_0 for vf0 on p6p1
NIC1_VF="${NIC1}vf0"
NIC2_VF="${NIC2}vf0"



#config end 
################################################################################
