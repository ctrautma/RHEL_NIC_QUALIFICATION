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

from sriov import SRIOV
import plumbum
import ethtool
import sys
import time
import shlex
import subprocess
import libvirt
from shell import shell
from shell import Shell
from plumbum import local



def get_local_command_object(cmd_string):
    if not cmd_string:
        return None
    cmd_list = shlex.split(cmd_string)
    cmd_obj = local[cmd_list[0]]
    return cmd_obj.__getitem__(cmd_list[1:])


class COMMON_SRIOV(SRIOV):

    def __init__(self):
        super(COMMON_SRIOV,self).__init__()

    @staticmethod
    def get_pf_name_from_pf_bus(pf_bus):
        if not pf_bus:
            return None
        temp_path = local.path("/sys/bus/pci/devices/{}/net".format(pf_bus))
        if temp_path.list()[0].name:
            return temp_path.list()[0].name
        else:
            return None

    @staticmethod
    def get_pf_bus_from_pf_name(pf_name):
        if not pf_name:
            return None
        bus_info = ethtool.get_businfo(pf_name)
        all_bus_info = []
        all_bus_info.append(bus_info)
        return all_bus_info

    @staticmethod
    def get_all_vf_list_from_pf_bus( pf_bus):
        if not pf_bus:
            return None
        all_vf_name_path = []
        all_vf_name = []
        str_path = "/sys/bus/pci/devices/{}/".format(pf_bus)
        path = local.path(str_path)
        for i in path:
            if str(i.name).startswith("virtfn"):
                all_vf_name_path.append("/sys/bus/pci/devices/{}/{}/net/".format(pf_bus, i.name))
        for vf_name_path in all_vf_name_path:
            for t in local.path(vf_name_path):
                all_vf_name.append(t.name)
        return all_vf_name

    @staticmethod
    def create_vfs( pf_bus, num):
        if not pf_bus or not num:
            return None
        pf_name = COMMON_SRIOV.get_pf_name_from_pf_bus(pf_bus)
        vf_obj = local.path("/sys/bus/pci/devices/{}/sriov_numvfs".format(pf_bus))
        if vf_obj.read() != 0:
            vf_obj.write("0")
            time.sleep(3)
        vf_obj.write(num)        
        shell("ip li set {} up".format(pf_name))
        shell("ip li show {}".format(pf_name))
        return 0

    @staticmethod
    def remove_vf_from_pf_bus( pf_bus):
        if not pf_bus:
            return None
        f = local.path("/sys/bus/pci/devices/{}/sriov_numvfs".format(pf_bus))
        if f.exists():
            return f.write(0)

    @staticmethod
    def get_pf_name_from_vf_name( vf_name):
        if not vf_name:
            return None
        path = local.path("/sys/class/net/{}/device/physfn/net".format(vf_name))
        if path.exists():
            return path.list()[0].name
        else:
            return None

    @staticmethod
    def get_pf_bus_from_vf_name( vf_name):
        if not vf_name:
            return None
        pf_name = COMMON_SRIOV.get_pf_name_from_vf_name(vf_name)
        if pf_name:
            return ethtool.get_businfo(pf_name)
        else:
            return ""

    @staticmethod
    def attach_vf_to_vm( vf_name, vm, mac=None, vlan=None):
        if not vf_name or not vm:
            return None
        vf_bus = ethtool.get_businfo(vf_name)
        #bus-info: 0000:04:02.0
        import re
        vf_bus = re.sub("[.:]", "_", vf_bus)
        vf_nodedev = "pci_" + vf_bus
        sp_vf_domain = str(vf_bus).split("_")[0]
        sp_vf_bus = str(vf_bus).split("_")[1]
        sp_vf_slot = str(vf_bus).split("_")[2]
        sp_vf_func = str(vf_bus).split("_")[3]
        pf_name = COMMON_SRIOV.get_pf_name_from_vf_name(vf_name)
        sriov_num = local.path("/sys/class/net/{}/device/sriov_numvfs".format(pf_name)).read()
        sriov_num = int(sriov_num)
        vf_index = -1
        for i in range(sriov_num):
            temp = local.path("/sys/class/net/{}/device/virtfn{}/net".format(pf_name, i))
            name = temp.list()[0].name
            if name == vf_name:
                vf_index = i
                break
        if vf_index == -1:
            print("Here we can not find {}".format(vf_name))
            return None

        if mac:
            shell("ip link set {} vf {} mac {}".format(pf_name, vf_index, mac))


        vf_node_file=str(vf_nodedev) + ".xml"
        local.path(local.cwd / vf_node_file).touch()
        conf_xml_file=local.path(local.cwd / vf_node_file)
        config_info="""
        <interface type='hostdev' managed='yes'>
            <source>
                    <address type='pci' domain='0x{}' bus='0x{}' slot='0x{}' function='0x{}'/>
            </source>
            <mac address='{}'/>
            <vlan>
                <tag id='{}'/>
            </vlan>
        </interface>
        """.format(sp_vf_domain, sp_vf_bus, sp_vf_slot, sp_vf_func, mac, vlan)
        #print(config_info)
        import xml.etree.ElementTree as et
        conf_obj=et.fromstring(config_info)
        if not mac:
            for i in conf_obj:
                if i.tag == "mac":
                    conf_obj.remove(i)
                    continue
        if not vlan:
            for i in conf_obj:
                if i.tag == "vlan":
                    conf_obj.remove(i)
                    continue
        conf_xml_file.write(et.tostring(conf_obj))

        sh_cmd=shell("virsh attach-device {} {}".format(vm, vf_node_file))
        #print(sh_cmd)
        if sh_cmd.code != 0:
            #print(sh_cmd.code)
            return sh_cmd.code

    @staticmethod
    def detach_vf_from_vm( vm, xml_file):
        if not xml_file or not vm:
            return None
        sh=shell("virsh detach-device {} {}".format(vm, xml_file))
        return sh.code
