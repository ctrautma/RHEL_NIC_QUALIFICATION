#!/usr/bin/env python3


import os
import sys
import subprocess as sp
import json
import base64
import paramiko
import xml.etree.ElementTree as xml
import ethtool
from plumbum import local
from shell import shell
from shell import Shell


def run_and_getout(command):
    fd = sp.Popen(command, shell=True, stdout=sp.PIPE)
    return fd.communicate()[0]


class Tools(object):

    def __init__(self):
        self.default_code = sys.getdefaultencoding()
        pass
    

    def get_bus_from_name(name):
        if name:
            return ethtool.get_businfo(name)
        else:
            return ""
    def get_mac_from_name(name):
        if name:
            return ethtool.get_hwaddr(name)
        else:
            return ""

    def get_nic_name_from_mac(mac):
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


    """
    <cputune>
    <vcpupin cpuset="1" vcpu="8" />
    <vcpupin cpuset="2" vcpu="3" />
    <vcpupin cpuset="3" vcpu="4" />
    <emulatorpin cpuset="8" />
    </cputune>
	"""

    def update_vcpu(self, xml_file, index, value):
        tree = xml.parse(xml_file)
        item = tree.find("cputune")
        item[index].set(str("cpuset"), str(value))
        if index == 0:
            item[3].set("cpuset", str(value))
        tree.write(xml_file)

    """
	<numatune>
	<memory mode='strict' nodeset='0'/>
	</numatune>
	"""

    def update_numa(self, xml_file, value):
        tree = xml.parse(xml_file)
        item = tree.find("numatune")
        item[0].set("nodeset", str(value))
        tree.write(xml_file)

    """
	<interface type='bridge'>
      <mac address='52:54:00:bb:63:7b'/>
      <source bridge='virbr0'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
    </interface>
	<interface type='vhostuser'>
      <mac address='52:54:00:11:8f:ea'/>
      <source type='unix' path='/tmp/vhost0' mode='server'/>
      <model type='virtio'/>
      <driver name='vhost' iommu='on' ats='on'/>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </interface>
	<interface type='hostdev' managed='yes'>
            <source>
                    <address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
            </source>
            <mac address='${mac}'/>
            <vlan>
                <tag id='${vlan}'/>
            </vlan>
        </interface>
	"""

    def update_vhostuser_interface(self, xml_file, mac, slot):
        tree = xml.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "vhostuser":
                item[0].set("address", str(mac))
                item[4].set("slot", str(slot))
        tree.write(xml_file)

    """
        <interface type='hostdev' managed='yes'>
                <mac address='52:54:00:7e:f4:6d'/>
                <driver name='vfio'/>
                <source>
                <address type='pci' domain='0x0000' bus='0x04' slot='0x10' function='0x1'/>
                </source>
                <alias name='hostdev1'/>
                <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
        </interface>
    """

    def get_pci_address_of_vm_hostdev(self, xml_file, index=0):

        all_hostdev_item = []
        tree = xml.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "hostdev":
                all_hostdev_item.append(item)
        if len(all_hostdev_item) > index:
            all_str = ""
            for i in list(all_hostdev_item[index]):
                if i.tag == "address" and i.get("type") == "pci":
                    all_str += str(i.get("domain"))[2:]
                    all_str += ":"
                    all_str += str(i.get("bus"))[2:]
                    all_str += ":"
                    all_str += str(i.get("slot"))[2:]
                    all_str += "."
                    all_str += str(i.get("function"))[2:]
                    break
            return all_str
        else:
            return ""

    """
	<interface type='hostdev' managed='yes'>
		<mac address='52:54:00:7e:f4:6d'/>
		<driver name='vfio'/>
		<source>
			<address type='pci' domain='0x0000' bus='0x04' slot='0x10' function='0x1'/>
		</source>
	<alias name='hostdev1'/>
	<address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
	</interface>
	"""

    def get_mac_address_of_vm_hostdev(self, xml_file, index=0):
        all_hostdev_item = []
        tree = xml.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "hostdev":
                all_hostdev_item.append(item)
        if len(all_hostdev_item) > index:
            all_str = ""
            for i in list(all_hostdev_item[index]):
                if i.tag == "mac":
                    all_str = str(i.get("address"))
                    break
            return all_str
        else:
            return ""

    def get_isolate_cpus(self):
        """Here Get all cpu from this system without cpu0"""

        command = "cat /proc/cpuinfo | grep processor | awk '{print $NF}'"
        out = run_and_getout(command)
        str_out = out.decode(self.default_code).replace('\n', ' ').strip()
        str_out = str(str_out)
        if str_out[0] == "0":
            return str_out[2:]
        else:
            return str_out

    def get_isolate_cpus_with_nic(self, nic_name):
        """
            First get cpu numa node and then get cpu list without cpu 0
        """
        cmd = "cat /sys/class/net/{}/device/numa_node".format(str(nic_name))
        out = run_and_getout(cmd)
        cpu_cmd = "lscpu | grep 'NUMA node%s' | awk '{print $NF}'" % (
            str(int(out)))
        cpu_info = run_and_getout(cpu_cmd)
        str_out = cpu_info.decode(self.default_code).strip()
        # 0,1,2,3,4
        # 0-9,9-29
        temp_list = str(str_out).split(',')
        all_str = ""
        for i in temp_list:
            if '-' in i:
                start_index = int(str(i).split('-')[0])
                last_index = int(str(i).split('-')[-1])+1
                all_str += " ".join([str(i)
                                     for i in range(start_index, last_index)]) + " "
            else:
                all_str += str(i)
                all_str += " "

        all_str = all_str.strip()
        if all_str[0] == "0":
            return all_str[2:]
        else:
            return all_str

    def get_pmd_masks(self, str_cpulist):
        ret_val = 0x0
        if str_cpulist == None or str_cpulist == "":
            return 0x0
        else:
            if isinstance(str_cpulist, str):
                for i in str_cpulist.split():
                    ret_val |= 0x1 << int(i)
                return hex(ret_val)
            else:
                ret_val |= 0x1 << int(str_cpulist)
                return hex(ret_val)
                pass
        pass

if __name__ == '__main__':
    import fire
    fire.Fire(Tools)
