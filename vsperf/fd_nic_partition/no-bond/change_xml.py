import xml.etree.ElementTree as ET
from subprocess import Popen, PIPE
import nic_info
def update_xml(xml_file, node, value):
    tree = ET.parse(xml_file)
    root = tree.getroot()

    for child in root:
       if child.tag == node:
           index=0
           for c in child.getchildren():
               if value[index]:
                   c.attrib = value[index].items()[0][1]
               index += 1
    tree.write(xml_file)

def run_shell(cmd):
            return Popen([cmd], shell=True, stdout=PIPE, stderr=PIPE).communicate()[0]

if __name__ == '__main__':
    try:
        guest1_cpu = run_shell("python2 get_pmd.py --cmd guest1_pmd --nic "+ nic_info.NIC1 +" --cpu "+nic_info.VCPUS)
        guest2_cpu = run_shell("python2 get_pmd.py --cmd guest2_pmd --nic "+ nic_info.NIC1 +" --cpu "+nic_info.VCPUS)
    except Exception,e:
        print(e)
        print("run get_pmd.py failed")
    guest1_cpu = guest1_cpu.strip("[(")
    guest1_cpu = guest1_cpu.strip("\n")
    guest1_cpu = guest1_cpu.strip(")]")
    guest1_cpu = guest1_cpu.replace("'","")
    guest1_cpu_list = guest1_cpu.split(",")
    guest2_cpu = guest2_cpu.strip("[(")
    guest2_cpu = guest2_cpu.strip("\n")
    guest2_cpu = guest2_cpu.strip(")]")
    guest2_cpu = guest2_cpu.replace("'","")
    guest2_cpu_list = guest2_cpu.split(",")
    if nic_info.VCPUS == '3':
        a1=guest1_cpu_list[0]
        b1=guest1_cpu_list[1].strip(' ')
        c1=guest1_cpu_list[2].strip(' ')
        d=nic_info.NUMA
        a2=guest2_cpu_list[0]
        b2=guest2_cpu_list[1].strip(' ')
        c2=guest2_cpu_list[2].strip(' ')
        value1 = [
            {"vcpupin" : {'cpuset': '0', 'vcpu': a1}},
            {"vcpupin" : {'cpuset': '1', 'vcpu': b1}},
            {"vcpupin" : {'cpuset': '2', 'vcpu': c1}},
            {"emulatorpin" : {'cpuset' : a1}}
        ]
        value2 = [
            {"vcpupin" : {'cpuset': '0', 'vcpu': a2}},
            {"vcpupin" : {'cpuset': '1', 'vcpu': b2}},
            {"vcpupin" : {'cpuset': '2', 'vcpu': c2}},
            {"emulatorpin" : {'cpuset' : a2}}
        ]
    update_xml("guest1.xml", "cputune", value1)
    update_xml("guest2.xml", "cputune", value2)

    value = [{"memory":{"mode":"strict","nodeset": d}}]
    update_xml("guest1.xml", "numatune", value)
    update_xml("guest2.xml", "numatune", value)
