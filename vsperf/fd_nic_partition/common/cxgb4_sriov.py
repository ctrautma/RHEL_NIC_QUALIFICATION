#!/usr/bin/env python

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   common_sriov.py of /kernel/networking/fd_nic_partition/common/
#   Author: Hekai Wang <hewang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
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


from common_sriov import COMMON_SRIOV
import plumbum
import ethtool
from plumbum import local
import time
import shlex
import subprocess
import libvirt
from shell import shell
from shell import Shell


class cxgb4_sriov(COMMON_SRIOV):

    def __init__(self):
        super(cxgb4_sriov,self).__init__()

    @staticmethod
    def get_pf_name_from_pf_bus(pf_bus):
        return COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)

    #return pf bus info to create vf
    @staticmethod
    def get_pf_bus_from_pf_name( pf_name):
        if not pf_name:
            return None
        
        bus_info = ethtool.get_businfo(pf_name)
        #driver = ethtool.get_module(pf_name)
        """
        FIX_ME if new NIC is introduced.
        For Chelsio T5/T4 adapters, the physical functions are currently assigned as:
        Physical functions 0 - 3: for the SR-IOV functions of the adapter
        Physical function 4: for all NIC functions of the adapter
        Physical function 5: for iSCSI
        Physical function 6: for FCoE
        Physical function 7: Currently not assigned
        "Chelsio T5/T4 Unified Wire for Linux - Installation and User's Guide
        """
        all_bus_info = []
        for i in [0, 1, 2, 3]:
            all_bus_info.append(bus_info[:-1]+str(i))
        return all_bus_info

    @staticmethod
    def get_all_vf_list_from_pf_bus(pf_bus):
        return COMMON_SRIOV.get_all_vf_list_from_pf_bus(pf_bus)

    @staticmethod
    def create_vfs( pf_bus, num):        
        COMMON_SRIOV.create_vfs(pf_bus,num)
        all_vf_name_list = cxgb4_sriov.get_all_vf_list_from_pf_bus(pf_bus)
        pf_name = cxgb4_sriov.get_pf_name_from_pf_bus(pf_bus)
        for vf in all_vf_name_list:
            shell("echo 0 /proc/sys/net/ipv6/conf/{}/accept_dad".format(vf))
            shell("echo 0 > /proc/sys/net/ipv6/conf/{}/dad_transmits".format(vf))
        shell("ethtool --set-priv-flags {} port_tx_vm_wr on".format(pf_name))
        shell("ip link set {} up".format(pf_name))
        shell("ip link show {}".format(pf_name))

    @staticmethod
    def remove_vf_from_pf_bus(pf_bus):
        return COMMON_SRIOV.remove_vf_from_pf_bus(pf_bus)

    @staticmethod
    def get_pf_name_from_vf_name(vf_name):
        return COMMON_SRIOV.get_pf_name_from_vf_name(vf_name)

    @staticmethod
    def get_pf_bus_from_vf_name(vf_name):
        return COMMON_SRIOV.get_pf_bus_from_vf_name(vf_name)

    @staticmethod
    def attach_vf_to_vm(vf_name, vm, mac=None, vlan=None):
        return COMMON_SRIOV.attach_vf_to_vm(vf_name,vm,mac,vlan)

    @staticmethod
    def detach_vf_from_vm(vm,xml_file):
        return COMMON_SRIOV.detach_vf_from_vm(vm,xml_file)
