import sys, getopt
from subprocess import Popen, PIPE
import os

def usages():
    print """
usage 1: caculate hex mask
python get_pmd.py --cmd host_pmd --nic enp1s0f0 --pmd 8  

usage 2:
python get_pmd.py --cmd guest1_pmd --nic enp1s0f0 --cpu 9

usage 3:
python get_pmd.py --cmd dpdk_args --nic enp1s0f0

usage 4:
python get_pmd.py --cmd spec_dpdk_args --nic enp1s0f0

usage 5:
python get_pmd.py --cmd last_cpu --nic enp1s0f0 --cpu 4

usage 5:
python get_pmd.py --cmd dpdk_config --nic enp1s0f0

usage 6:
python get_pmd.py --cmd guest2_pmd --nic enp1s0f0 --cpu 9
    """

cmd=None
pmd_num=None
cpu_num=None
nic=None

opts, args = getopt.getopt(sys.argv[1:], 'm:p:n:c:', ['cmd=', 'pmd=', 'nic=', 'cpu='])
if len(opts) == 0:
    print "Please input correct params!"
    usages()
    sys.exit()


for op, value in opts:
    if op in ('-m', '--cmd'):
        cmd = value
    elif op in ('-p', '--pmd'):
        pmd_num = value
    elif op in ('-n', '--nic'):
        nic = value
    elif op in ('-c', '--cpu'):
        cpu_num = value

SOCKET = 2


def run_shell(cmd):
    return Popen([cmd], shell=True, stdout=PIPE, stderr=PIPE).communicate()[0]

def get_core_map():
    sockets = []
    cores = []
    core_map = {}

    fd=open("/proc/cpuinfo")
    lines = fd.readlines()
    fd.close()

    core_details = []
    core_lines = {}
    for line in lines:
        if len(line.strip()) != 0:
            name, value = line.split(":", 1)
            core_lines[name.strip()] = value.strip()
        else:
            core_details.append(core_lines)
            core_lines = {}

    for core in core_details:
        for field in ["processor", "core id", "physical id"]:
            if field not in core:
                print "Error getting '%s' value from /proc/cpuinfo" % field
                sys.exit(1)
            core[field] = int(core[field])

        if core["core id"] not in cores:
            cores.append(core["core id"])
        if core["physical id"] not in sockets:
            sockets.append(core["physical id"])
        key = (core["physical id"], core["core id"])
        if key not in core_map:
            core_map[key] = []
        core_map[key].append(core["processor"])

    return core_map, cores

def cpus():
    return len(data) * 2

def get_cores(data):
    sort_core = [] 
    for k in data.keys():
        sort_core.append(k[1])
    sort_core = list(set(sort_core))
    sort_core.reverse()
    return sort_core

def pmdMask(core_map, pmd_num, socket):
    rlt = []
    c = get_cores(core_map)
    tmp = int(pmd_num) / 2
    for i in c:
        rlt.extend(list(core_map[(int(socket), i)]))
        tmp = tmp - 1
        if tmp <= 0:
            break
    return rlt 

def host_pmd():
    data, _ = get_core_map()
    socket = numa(nic)
    r = 0
    for i in pmdMask(data, pmd_num, socket):
        r += 2 ** i
    rlt = str(hex(r))
    if rlt[-1] == 'L':
        rlt = rlt[:-1]
    return rlt

def numa(nic):
    if nic is None:
        return None
    else:
        numa_file = "/tmp/numa"
        if os.path.exists(numa_file):
            return int(run_shell("cat %s" % numa_file))
        else:
            node = int(run_shell("cat /sys/class/net/%s/device/numa_node" % nic))
            with open(numa_file, 'wt') as f:
                f.write(str(node))
            return node 

def guest1_pmd():
    rlt = []
    global nic, cpu_num
    var_numa = numa(nic)
    data, cores = get_core_map()
    
    for i in range(len(cores)):
        if i == 0:
            continue
        elif i == 1:
            rlt.append(str(data[(var_numa, cores[i])][0]))
        else:
            for tmp in data[(var_numa, cores[i])]:
                rlt.append(str(tmp))
            if len(rlt) >= int(cpu_num):
                break
    return [tuple(rlt)]

def guest2_pmd():
    rlt = []
    global nic, cpu_num
    var_numa = numa(nic)
    data, cores = get_core_map()
    for i in range(len(cores)):
        if i == 0:
            continue
        elif i == 1:
            rlt.append(str(data[(var_numa, cores[i])][1]))
        else:
            for tmp in data[(var_numa, cores[i+1])]:
                rlt.append(str(tmp))
            if len(rlt) >= int(cpu_num):
                break
    return [tuple(rlt)]


def dpdk_config():
    rlt = {'dpdk-init' : 'true','dpdk-lcore-mask' : '',}
    global nic
    var_numa = numa(nic)
    data, cores = get_core_map()
    hex_mask = data[(var_numa, cores[0])][0]
    rlt['dpdk-lcore-mask'] = str(hex(2 ** hex_mask))
    return rlt

def dpdk_args():
    rlt = ['-c', '', '-n', '4', '--socket-mem 1024,1024']
    global nic
    var_numa = numa(nic)
    data, cores = get_core_map()
    hex_mask = data[(var_numa, cores[0])][0]
    rlt[1] = str(hex(2 ** hex_mask))
    return rlt

def spec_dpdk_args():
    rlt = ['-l', '', '-n', '4', '--socket-mem 1024,1024']
    global nic
    var_numa = numa(nic)
    data, cores = get_core_map()
    length = len(cores)
    tmp = []
    for i in range(length - 3, length):
        tmp.append(str(data[(var_numa, cores[i])][0]))
    rlt[1] = ','.join(tmp)
    return rlt  

def last_cpu():
    global nic, cpu_num
    data, _ = get_core_map()
    socket = numa(nic)
    return pmdMask(data, cpu_num, socket)

if cmd == 'host_pmd':
    print host_pmd()
elif cmd == 'guest1_pmd':
    print guest1_pmd()
elif cmd == 'guest2_pmd':
    print guest2_pmd()
elif cmd == 'dpdk_args':
    print dpdk_args()
elif cmd == 'spec_dpdk_args':
    print spec_dpdk_args()
elif cmd == 'last_cpu':
    print last_cpu()
elif cmd == 'dpdk_config':
    print dpdk_config()
