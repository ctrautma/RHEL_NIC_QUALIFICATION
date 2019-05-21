#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   mlx_sriov.py of /kernel/networking/fd_nic_partition/common/mlx_sriov.py
#   Author: Hekai Wang <hewang@redhat.com>
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


import plumbum
import ethtool
import sys
from plumbum import local
import time
import shlex
import subprocess
import libvirt
from shell import shell
from shell import Shell
from common_sriov import COMMON_SRIOV

class mlx_sriov(COMMON_SRIOV):

    def __init__(self):
        super(mlx_sriov,self).__init__()

    @staticmethod
    def get_pf_name_from_pf_bus( pf_bus):
        return COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)

    @staticmethod
    def get_pf_bus_from_pf_name( pf_name):
        return COMMON_SRIOV.get_pf_bus_from_pf_name(pf_name)
    
    @staticmethod
    def get_all_vf_list_from_pf_bus( pf_bus):
        return COMMON_SRIOV.get_all_vf_list_from_pf_bus(pf_bus)

    @staticmethod
    def create_vfs( pf_bus, num):
        if not pf_bus or not num:
            return None
        pf_name = COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)
        driver = ethtool.get_module(pf_name)
        if driver == "mlx4_en":
            num_vfs="$num_vfs,$num_vfs,0"
            libmlx4_conf_file = local.path("/etc/modprobe.d/libmlx4.conf")
            if not "CMDLINE_OPTS" in libmlx4_conf_file.read():
                config_info="""
                install mlx4_core /sbin/modprobe --ignore-install mlx4_core  $CMDLINE_OPTS && (if [ -f /usr/libexec/mlx4-setup.sh -a -f /etc/rdma/mlx4.conf ]; then /usr/libexec/mlx4-setup.sh < /etc/rdma/mlx4.conf; fi; /sbin/modprobe mlx4_en; /sbin/modprobe mlx4_ib)
                """
                libmlx4_conf_file.write(config_info)
                shell("modprobe -r mlx4_en; modprobe -r mlx4_ib;  modprobe -r mlx4_core")
                shell("modprobe mlx4_core num_vfs={} probe_vf={}".format(num_vfs,num_vfs))
        else:
            vf_obj = local.path("/sys/bus/pci/devices/{}/sriov_numvfs".format(pf_bus))
            if vf_obj.is_file():
                if vf_obj.read() != 0:
                    vf_obj.write(0)
                time.sleep(3)
                vf_obj.write(num)
        shell("ip li set {} up".format(pf_name))
        shell("ip li show {}".format(pf_name))
        return 0

    @staticmethod
    def remove_vf_from_pf_bus( pf_bus):
        return COMMON_SRIOV.remove_vf_from_pf_bus(pf_bus)

    @staticmethod
    def get_pf_name_from_vf_name( vf_name):
        return COMMON_SRIOV.get_pf_name_from_vf_name(vf_name)

    @staticmethod
    def get_pf_bus_from_vf_name( vf_name):
        return COMMON_SRIOV.get_pf_bus_from_vf_name(vf_name)

    @staticmethod
    def attach_vf_to_vm( vf_name, vm, mac, vlan):
        return COMMON_SRIOV.attach_vf_to_vm(vf_name,vm,mac=None,vlan=None)
        # from console import Console
        # cmd_string="""
        # export NIC_TEST=$(ip link show | grep {} -B1 | head -n1 | awk '{print $2}' | sed 's/://)\r\n;
        # echo 0 > /proc/sys/net/ipv6/conf/${NIC_TEST}/accept_dad\r\n;
        # echo 0 > /proc/sys/net/ipv6/conf/${NIC_TEST}/dad_transmits\r\n;
        # """.format(mac)
        # my_console = Console("qemu:///system", vf_name, "root", "password")
        # my_console.update_cmd_list(cmd_string)
        # my_console.runconsole()

    @staticmethod
    def detach_vf_from_vm( vm, xml_file):
        return COMMON_SRIOV.detach_vf_from_vm(vm,xml_file)
