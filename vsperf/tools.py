#!/usr/bin/env python3


import os
import sys
import subprocess as sp
import json
import base64
import paramiko
import xml.etree.ElementTree as ET
import ethtool
from plumbum import local
from shell import shell
from shell import Shell
import pexpect


def run_and_getout(command):
    fd = sp.Popen(command, shell=True, stdout=sp.PIPE)
    return fd.communicate()[0]


class Tools(object):

    def __init__(self):
        self.default_code = sys.getdefaultencoding()
        pass

    def get_bus_from_name(self, name):
        if name:
            return ethtool.get_businfo(name)
        else:
            return ""

    def get_mac_from_name(self, name):
        if name:
            return ethtool.get_hwaddr(name)
        else:
            return ""

    def get_nic_name_from_mac(self, mac):
        if not mac:
            return "name-error"
        temp_path = local.path("/sys/class/net")
        for i in temp_path:
            temp_mac = ethtool.get_hwaddr(str(i.name))
            if temp_mac == mac:
                return i.name

        return "name-error"

    def get_random_mac_addr(self):
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

    def xml_add_vcpupin_item(self, xml_file, num):
        """
        <vcpu placement="static">3</vcpu>
        <cputune>
            <vcpupin cpuset="1" vcpu="0" />
            <vcpupin cpuset="2" vcpu="1" />
            <vcpupin cpuset="3" vcpu="2" />
        </cputune>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        vcpu_item = ET.ElementPath.find(root, "./vcpu")
        current_num = 0
        if None != vcpu_item:
            current_num = int(vcpu_item.text)
            vcpu_item.text = str(num)
        item = ET.ElementPath.find(root, "./cputune")
        sub_item = ET.ElementPath.find(root, "./cputune/vcpupin")
        if num > current_num:
            for i in range(num-current_num):
                item.append(sub_item)
        sub_item_list = list(item)
        for i in range(sub_item_list.__len__()):
            sub_item_list[i].set(str("vcpu"), str(i))
            sub_item_list[i].set(str("cpuset"), str(i))
        sub_item_list.sort()

        print(ET.tostringlist(item))
        tree.write(xml_file)
        pass

    def update_vcpu(self, xml_file, index, value):
        """
        <cputune>
        <vcpupin cpuset="1" vcpu="8" />
        <vcpupin cpuset="2" vcpu="3" />
        <vcpupin cpuset="3" vcpu="4" />
        </cputune>
        """
        tree = ET.parse(xml_file)
        item = tree.find("cputune")
        item[index].set(str("cpuset"), str(value))
        tree.write(xml_file)

    def update_numa(self, xml_file, value):
        """
        <numatune>
        <memory mode='strict' nodeset='0'/>
        </numatune>
        """
        tree = ET.parse(xml_file)
        item = tree.find("numatune")
        item[0].set("nodeset", str(value))
        tree.write(xml_file)

    def update_image_source(self, xml_file, image_name):
        """
        <devices>
            <emulator>/usr/libexec/qemu-kvm</emulator>
            <disk device="disk" type="file">
                    <driver name="qemu" type="qcow2" />
                    <source file="/root/rhel.qcow2" />
                    <target bus="virtio" dev="vda" />
                    <address bus="0x01" domain="0x0000" function="0x0" slot="0x00" type="pci" />
            </disk>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        source_item = ET.ElementPath.find(root, "./devices/disk/source")
        source_item.set(str("file"), str(image_name))
        tree.write(xml_file)

    def login_vm_and_run_cmds(self,vm_domain,cmds,prompt=None):
        patterm = ["login:","Password:","]#",pexpect.EOF, pexpect.TIMEOUT,r"Escape character is \^]"]
        child = pexpect.spawn("virsh console gg")
        child.logfile = None
        child.logfile_read=sys.stdout.buffer
        child.logfile_send=None
        err_flag = False
        if None == prompt:
            prompt="]#"
        while True:
            index = child.expect(patterm)
            if index == 0:
                child.sendline("root")
            elif index == 1:
                child.sendline("redhat")
            elif index == 2:
                break
            elif index == 3:
                break
            elif index == 4:
                print("Timeout error")
                err_flag = True
                break
            elif index == 5:
                child.sendline("")
                child.send(chr(3))
            else:
                err_flag = True
                print("unknow virsh console return str")
                child.send(chr(3))
                break
        if err_flag:
            return -1
        cmd_list = cmds.split('\n')
        #print(cmd_list)
        for c in cmd_list:
            child.sendline(c.strip('{ }'))
            child.expect(prompt)
            if prompt == "]#":
                child.sendline("echo $?")
                child.expect(prompt)
        sys.stdout.flush()
        child.close()
        return 0

    def update_vhostuser_interface(self, xml_file, mac, slot):
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
        tree = ET.parse(xml_file)
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
        tree = ET.parse(xml_file)
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
        tree = ET.parse(xml_file)
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


if __name__ == '__main__':
    import fire
    fire.Fire(Tools)
