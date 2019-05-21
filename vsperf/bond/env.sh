#!/bin/bash

#SYSTEM_CONFIG
################################################################
SYSTEM_VERSION=${SYSTEM_VERSION:-"RHEL-8.0-20181029.3"}
# VM image OVS DPDK BONDING TEST 
IMAGE_GUEST=${IMAGE_GUEST:-"http://netqe-bj.usersys.redhat.com/share/wanghekai/image/rhel8-1Q-img.qcow2"}
################################################################

#PLEASE KEEP THE FOLLOW SECTION CONFIG FIXED
#################################################################
#BOND_TEST_MODE:xena,iperf
#xena means with xena or trex test the throughput perforance
#iperf means two hosts test iperf performance between client and server
BOND_TEST_MODE=${BOND_TEST_MODE:-xena}
#ovs bond mode : balance_tcp ,active_backup,balance_slb
OVS_BOND_MODE_BALANCE_TCP="balance-tcp"
OVS_BOND_MODE_ACITVE_BACKUP="active-backup"
OVS_BOND_MODE_BALANCE_SLB="balance-slb"
##################################################################

#BOND_TEST_MODE_IPERF CONFIG
##################################################################
SERVER_VCPUS=${SERVER_VCPUS:-2}
CLIENT_VCPUS=${CLIENT_VCPUS:-2}
CLIENT_GUEST_IP=${CLIENT_GUEST_IP:-192.168.99.200}
SERVER_GUEST_IP=${SERVER_GUEST_IP:-192.168.99.201}
# hostname for the machines
# The name must be the same as shown by linux command hostname
# and the names for CLIENTS and SERVERS must not be the same
SERVERS=${SERVERS:-"dell-per730-54.rhts.eng.pek2.redhat.com"}
CLIENTS=${CLIENTS:-"dell-per730-18.rhts.eng.pek2.redhat.com"}
##################################################################

#NOTICE PLEASE FIX YOUR CONFIG FROM HERE BELOW
#CONN_TYPE netscout only or null
CONN_TYPE=${CONN_TYPE:-netscout}
NETSCOUT_HOST=${NETSCOUT_HOST:-10.73.88.9}
#traffic_type ,can  be xena trex
TRAFFIC_TYPE=${TRAFFIC_TYPE:-xena}
################################################################################
#TRAFFIC TREX CONFIG 
#ONLY ENABLED WITH TRAFFIC_TYPE==trex
#the host ip that  started the t-rex-64 -i with this host
TREX_SERVER_IP=${TREX_SERVER_IP:-10.73.88.57}
TREX_SERVER_PASSWORD=${TREX_SERVER_PASSWORD:-QwAo2U6GRxyNPKiZaOCx}

#TOPO PORT NAME
#NOTE: IF Your environment is NOT connect with netscout , do not fill the following item
#THE FOLLOWING SECTION ITME ONLY ENABLED WITH NETSCOUT
TRAFFIC_PORT=${TRAFFIC_PORT:-XENA_M7P0}
SERVER_PORT_ONE=${SERVER_PORT_ONE:-01.01.05}
SERVER_PORT_TWO=${SERVER_PORT_TWO:-01.01.06}
SWITCH_PORT_ONE=${SWITCH_PORT_ONE:-5010_Eth3}
SWITCH_PORT_TWO=${SWITCH_PORT_TWO:-5010_Eth4}
SWITCH_PORT_THREE=${SWITCH_PORT_THREE:-5010_Eth5}
SWITCH_PORT_FOUR=${SWITCH_PORT_FOUR:-5010_Eth6}
CLIENT_PORT_ONE=${CLIENT_PORT_ONE:-01.01.45}
CLIENT_PORT_TWO=${CLIENT_PORT_TWO:-01.01.46}

########################################################################################
#OVS DPDK BONDING SWITCH INFO CONFIG
SWITCH_NAME=${SWITCH_NAME:-5010}
SWITCH_PORT_NAME=${SWITCH_PORT_NAME:-Eth1/3 Eth1/4}
SW_PORT_ONE_NAME=`echo $SWITCH_PORT_NAME| awk '{print $1}'`
SW_PORT_TWO_NAME=`echo $SWITCH_PORT_NAME| awk '{print $2}'`


#CLIENT AND SERVER HOST NIC CONFIG
NIC_DRIVER=${NIC_DRIVER:-ixgbe}
SERVER_NIC1_MAC=${SERVER_NIC1_MAC:-b4:96:91:14:b0:14}
SERVER_NIC2_MAC=${SERVER_NIC2_MAC:=b4:96:91:14:b0:16}
CLIENT_NIC1_MAC=${CLIENT_NIC1_MAC:-f8:f2:1e:02:c4:a0}
CLIENT_NIC2_MAC=${CLIENT_NIC2_MAC:-f8:f2:1e:02:c4:a2}

#OPENVSWITCH AND DPDK CONFIG 
CONTAINER_SELINUX_URL=${CONTAINER_SELINUX_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/container-selinux/2.77/1.el7_6/noarch/container-selinux-2.77-1.el7_6.noarch.rpm"}
OVS_SELINUX_URL=${OVS_SELINUX_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch-selinux-extra-policy/1.0/3.el7fdp/noarch/openvswitch-selinux-extra-policy-1.0-3.el7fdp.noarch.rpm'}
OVS_URL=${OVS_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.9.0/36.el7fdp/x86_64/openvswitch-2.9.0-36.el7fdp.x86_64.rpm'}
PYTHON_OVS_URL=${PYTHON_OVS_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.9.0/36.el7fdp/noarch/python-openvswitch-2.9.0-36.el7fdp.noarch.rpm'}
OVS_TEST_URL=${OVS_TEST_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.9.0/36.el7fdp/noarch/openvswitch-test-2.9.0-36.el7fdp.noarch.rpm'}
DPDK_URL=${DPDK_URL:-'http://download.eng.pek2.redhat.com/brewroot/packages/dpdk/17.11/7.el7/x86_64/dpdk-17.11-7.el7.x86_64.rpm'}
DPDK_TOOL_URL=${DPDK_TOOL_URL:-'http://download.eng.pek2.redhat.com/brewroot/packages/dpdk/17.11/7.el7/x86_64/dpdk-tools-17.11-7.el7.x86_64.rpm'}
DRIVERCTL_URL=${DRIVERCTL_URL:-'http://download-node-02.eng.bos.redhat.com/brewroot/packages/driverctl/0.95/1.el7fdparch/noarch/driverctl-0.95-1.el7fdparch.noarch.rpm'}
#CONFIG END , DO NOT EDIT THE FOLLOW CODE UNLESS YOU SURE YOU CAN !!!

DPDK_VERSION=${DPDK_VERSION:-1711-14}
GUEST_DPDK_VERSION=${GUEST_DPDK_VERSION:-1711-14}
##################################################################################################