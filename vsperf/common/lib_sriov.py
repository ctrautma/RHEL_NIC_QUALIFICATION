#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib_sriov.py of /kernel/networking/fd_nic_partition/common/
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

# helper for SR-IOV
import sys
import os
sys.path.append(os.getcwd())
from cxgb4_sriov import cxgb4_sriov
from mlx_sriov import mlx_sriov
from common_sriov import COMMON_SRIOV
import ethtool
import fire
from plumbum import local
from shell import shell
from shell import Shell


class LIB_SRIOV(COMMON_SRIOV):

    def __init__(self):
        super(LIB_SRIOV,self).__init__()
        pass
    
    @staticmethod
    def sriov_get_pf_bus_from_pf_name(name):
        if not name:
            return ""
        else:
            driver = ethtool.get_module(name)
            if "cxgb" in driver:
                return cxgb4_sriov.get_pf_bus_from_pf_name(name)
            elif "mlx" in driver:
                return mlx_sriov.get_pf_bus_from_pf_name(name)
            else:
                return COMMON_SRIOV.get_pf_bus_from_pf_name(name)

    @staticmethod
    def sriov_get_bus_from_name(name):
        if name:
            return ethtool.get_businfo(name)
        else:
            return ""
    @staticmethod
    def sriov_get_mac_from_name(name):
        if name:
            return ethtool.get_hwaddr(name)
        else:
            return ""

    @staticmethod
    def sriov_get_nic_name_from_mac(mac):
        if not mac:
            return "name-error"
        temp_path = local.path("/sys/class/net")
        for i in temp_path:
            temp_mac = ethtool.get_hwaddr(str(i.name))
            if temp_mac == mac:
                return i.name

        return "name-error"
        
    @staticmethod
    def get_random_mac_addr():
        import random
        mac = [
        0x52,
        0x54,
        0x11, 
        random.randint(0x00, 0xff), 
        random.randint(0x00, 0xff), 
        random.randint(0x00, 0xff)
        ]
        return ':'.join(map(lambda x: "{:02x}".format(x), mac))

    @staticmethod
    def sriov_create_vfs(pf_bus,num):
        pf_name = COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)
        driver = ethtool.get_module(pf_name)
        if "cxgb" in driver:
            return cxgb4_sriov.create_vfs(pf_bus,str(num))
        elif "mlx" in driver:
            return mlx_sriov.create_vfs(pf_bus,str(num))
        else:
            return COMMON_SRIOV.create_vfs(pf_bus,str(num))

    @staticmethod
    def sriov_remove_vfs_from_pf_bus(pf_bus):
        pf_name = COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)
        driver = ethtool.get_module(pf_name)
        if "cxgb" in driver:
            return cxgb4_sriov.remove_vf_from_pf_bus(pf_bus)
        elif "mlx" in driver:
            return mlx_sriov.remove_vf_from_pf_bus(pf_bus)
        else:
            return COMMON_SRIOV.remove_vf_from_pf_bus(pf_bus)
        pass
    @staticmethod
    def sriov_remove_vfs_from_pf_name(pf_name):
        all_pf_bus_info = COMMON_SRIOV.get_pf_bus_from_pf_name(pf_name)
        for pf_bus in all_pf_bus_info:
            LIB_SRIOV.sriov_remove_vfs_from_pf_bus(pf_bus)

    @staticmethod
    def sriov_attach_vf_to_vm(vf_name, vm, mac=None, vlan=None):
        driver = ethtool.get_module(vf_name)
        if "cxgb" in driver:
            return cxgb4_sriov.attach_vf_to_vm(vf_name,vm,mac,vlan)
        elif "mlx" in driver:
            return mlx_sriov.attach_vf_to_vm(vf_name,vm,mac,vlan)
        else:
            return COMMON_SRIOV.attach_vf_to_vm(vf_name,vm,mac,vlan)
        pass
    @staticmethod
    def sriov_detach_vf_from_vm(vm,xml_file):
        return COMMON_SRIOV.detach_vf_from_vm(vm,xml_file)

    @staticmethod
    def sriov_attach_pf_to_vm(pf_name,vm):
        if not pf_name or not vm:
            return None
        #driver = ethtool.get_module(pf_name)
        pf_bus = COMMON_SRIOV.get_pf_bus_from_pf_name(pf_name)
        #bus-info: 0000:04:02.0
        import re
        pf_bus = re.sub("[.:]", "_", pf_bus)
        pf_nodedev = "pci_" + pf_bus
        sp_pf_domain = str(pf_bus).split("_")[0]
        sp_pf_bus = str(pf_bus).split("_")[1]
        sp_pf_slot = str(pf_bus).split("_")[2]
        sp_pf_func = str(pf_bus).split("_")[3]

        pf_node_file=str(pf_nodedev) + ".xml"
        local.path(local.cwd / pf_node_file).touch()
        conf_xml_file=local.path(local.cwd / pf_node_file)
        config_info="""
        <interface type='hostdev' managed='yes'>
            <source>
                    <address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
            </source>
        </interface>
        """.format(sp_pf_domain, sp_pf_bus, sp_pf_slot, sp_pf_func)
        import xml.etree.ElementTree as xml
        conf_obj=xml.fromstring(config_info)
        conf_xml_file.write(xml.tostring(conf_obj))

        sh_cmd=shell("virsh attach-device {} {}".format(vm, pf_node_file))
        if sh_cmd.code != 0:
            return sh_cmd.code
    @staticmethod
    def sriov_detach_pf_from_vm(pf_bus,vm):
        import re
        pf_bus = re.sub("[.:]", "_", pf_bus)
        pf_nodedev = "pci_" + pf_bus
        return shell("virsh detach-device {} {}.xml".format(vm,pf_nodedev)).code

    @staticmethod
    def sriov_get_vf_list(pf_name):
        all_vf = []
        all_pf_bus = COMMON_SRIOV.get_pf_bus_from_pf_name(pf_name)
        for pf_bus in all_pf_bus:
            vf_name_list = COMMON_SRIOV.get_all_vf_list_from_pf_bus(pf_bus)
            all_vf.extend(vf_name_list)
        return all_vf
    
    @staticmethod
    def sriov_get_vf_name_from_pf(pf_name,index=0):
        """
        Get the special index vf name 
        """
        if not pf_name:
            return "vf_name_error"
        all_vf = []
        all_vf = LIB_SRIOV.sriov_get_vf_list(pf_name)
        if len(all_vf) > index:
            return all_vf[index]
        else:
            return ""


if __name__ == "__main__":
    import fire
    fire.Fire(LIB_SRIOV)
