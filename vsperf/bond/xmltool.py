#!/usr/bin/env python3


import os
import sys
import select
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


class XmlTool(object):

    def __init__(self):
        self.default_code = sys.getdefaultencoding()
        pass

    def xml_get_name(self,xml_file):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        name_item = ET.ElementPath.find(root,"./name")
        if name_item != None:
            return name_item.text
        else:
            return ""

    def xml_get_uuid_from_xml_file(self,xml_file):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        uuid_item = ET.ElementPath.find(root,"./uuid")
        if uuid_item != None:
            return uuid_item.text
        else:
            return ""

    def xml_update_guestname_and_uuid(self,xml_file,name,uuid):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        name_item = ET.ElementPath.find(root,"./name")
        uuid_item = ET.ElementPath.find(root,"./uuid")
        if name_item != None and name != None:
            name_item.text = str(name)
        if uuid_item != None and uuid != None:
            uuid_item.text = str(uuid)
        tree.write(xml_file)

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


    def format_item(self,info,format_list):
        if info:
            return str(info).format(*format_list)
        pass

    def add_item_from_xml(self, xml_file, parent_path, xml_info):
        tree = ET.parse(xml_file)
        item = ET.fromstring(xml_info)
        root = tree.getroot()
        parent_item = ET.ElementPath.find(root, parent_path)
        if parent_item:
            parent_item.append(item)
        tree.write(xml_file)
    
    def remove_item_from_xml(self,xml_file,path,index=None):
        tree = ET.parse(xml_file)
        root = tree.getroot()
        item_list = ET.ElementPath.findall(root,path)
        if None == index:
            for item in item_list:
                root.remove(item)
        else:
            root.remove(item_list[int(index)])
        tree.write(xml_file)
    

    def get_pci_address_of_vm_hostdev(self, xml_file, index=0):
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


    def get_mac_address_of_vm_hostdev(self, xml_file, index=0):
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


if __name__ == '__main__':
    import fire
    fire.Fire(XmlTool)
