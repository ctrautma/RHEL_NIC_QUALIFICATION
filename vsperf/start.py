#!/usr/bin/env python3

import os
import contextlib
import sys
import pprint
import base64
import time
import platform as pl
import shutil as sh
import subprocess as sp
from envbash import load_envbash
from plumbum import local
from functools import wraps
from bash import bash
import tools
import xmltool
from tee import StderrTee as errtee , StdoutTee as outtee


def get_env(var_name):
    return os.environ.get(var_name)

case_path = get_env("CASE_PATH")
system_version_id = int(get_env("SYSTEM_VERSION_ID"))

my_tool = tools.Tools()
xml_tool = xmltool.XmlTool()
work_pipe = get_env("work_pipe")
notify_pipe = get_env("notify_pipe")


def set_check(ret):
    def my_wrap(f):
        @wraps(f)
        def log_f_as_called(*args, **kwargs):
            # cur_time = time.asctime()
            my_command = f'{f.__name__} {args} {kwargs}'
            cmd = f""":: [  BEGIN   ] :: Running '{my_command}'"""
            log(cmd)
            value = f(*args, **kwargs)
            # cur_time = time.asctime()
            cmd = f""":: [  END   ] :: Running '{my_command}' RETURN {value}"""
            log(cmd)
            return value
        return log_f_as_called
    return my_wrap


def send_command(cmd):
    cmd = cmd + os.linesep
    try:
        with open(notify_pipe, "r") as rfd:
            rfd.read()
            with open(work_pipe, "w") as fd:
                fd.write(cmd)
                fd.flush()
    except IOError as e:
        print("*"*80)
        print("error find")
        print(cmd)
        print(e)
        print("*"*80)
    pass


def log(str_log):
    logs = str(str_log).split(os.linesep)
    for cmd in logs:
        cmd = f""" rlLog "{cmd}" """
        send_command(cmd)


def sh_run(cmd, str_ret_val="0"):
    cmd = """ rlRun  "{}" "{}" """.format(cmd, str_ret_val)
    send_command(cmd)
    pass


def sh_run_log(cmd, str_ret_val="0"):
    cmd = """ rlRun -l "{}" "{}" """.format(cmd, str_ret_val)
    send_command(cmd)
    pass


def run(cmd, str_ret_val="0"):
    cmds = cmd.split('\n')
    cmds = [i.strip() for i in cmds]
    for cmd in cmds:
        if len(cmd) > 0:
            sh_run(cmd, str_ret_val)
    pass


def runlog(cmd, str_ret_val="0"):
    cmds = cmd.split('\n')
    cmds = [i.strip() for i in cmds]
    for cmd in cmds:
        if len(cmd) > 0:
            sh_run_log(cmd, str_ret_val)
    pass


def shpushd(path):
    cmd = f"""rlRun "pushd {path}" """
    send_command(cmd)
    pass


def shpopd():
    cmd = "rlRun popd"
    send_command(cmd)
    pass


@contextlib.contextmanager
def pushd(path):
    shpushd(path)
    try:
        yield
    finally:
        shpopd()


@contextlib.contextmanager
def enter_phase(str):
    cmd = f""" rlPhaseStartTest '{str}' """
    send_command(cmd)
    time.sleep(3)
    try:
        yield
    finally:
        send_command("rlPhaseEnd")
        time.sleep(3)

###############################################################################################
###############################################################################################
###############################################################################################
###############################################################################################


def check_install(pkg_name):
    run("rpm -q {} || yum -y install {}".format(pkg_name, pkg_name))


@set_check(1)
def get_nic_name_from_mac(mac_addr):
    return my_tool.get_nic_name_from_mac(mac_addr)


@set_check(1)
def get_pmd_masks(str_cpus):
    return my_tool.get_pmd_masks(str_cpus)


@set_check(1)
def get_isolate_cpus(nic_name):
    return my_tool.get_isolate_cpus_with_nic(nic_name)

@set_check(0)
def enable_dpdk(nic1_mac, nic2_mac):
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    nic1_businfo = my_tool.get_bus_from_name(nic1_name)
    nic2_businfo = my_tool.get_bus_from_name(nic2_name)
    cmd = """
    modprobe -r vfio-pci
    modprobe -r vfio
    modprobe vfio-pci
    modprobe vfio
    """
    run(cmd,"0,1")
    import ethtool
    driver_name = ethtool.get_module(nic1_name)
    if driver_name == "mlx5_core":
        log("This Driver is Mallenox , So just return 0")
        return 0
    if os.path.exists("/usr/share/dpdk/usertools/dpdk-devbind.py"):
        log("using dpdk-devbind.py set the vfio-pci driver to nic")
        cmd = f"""
        /usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci {nic1_businfo}
        /usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci {nic2_businfo}
        /usr/share/dpdk/usertools/dpdk-devbind.py --status
        """
        run(cmd)
    else:
        log("using driverctl set the vfio-pci driver to nic")
        cmd = f"""
        driverctl -v set-override {nic1_businfo} vfio-pci
        sleep 3
        driverctl -v set-override {nic2_businfo} vfio-pci
        sleep 3
        driverctl -v list-devices | grep vfio-pci
        """
        run(cmd)
    pass

@set_check(0)
def clear_hugepage():
    hugepage_dir = bash("mount -l | grep hugetlbfs | awk '{print $3}'").value()
    run(f"rm -rf {hugepage_dir}/*")
    return 0

#################################################################################
#################################################################################
#################################################################################
#################################################################################


def os_check():
    if get_env("ID") != 'rhel':
        log("system distro not correct")
        return 1
    import getpass
    if getpass.getuser() != "root":
        log("User check ,must be logged in as root")
        return 1
    run("""rpm -ivh lrzip-0.616-5.el7.x86_64.rpm || echo "lrzip install" "Failed to install lrzip"  """)
    pass


def log_folder_check():
    log_folder = "/root/RHEL_NIC_QUAL_LOGS"
    if not os.path.exists(log_folder):
        os.mkdir(log_folder)
    time_stamp = time.strftime("%Y-%m-%d-%H-%M-%S")
    nic_log_folder = log_folder + "/" + time_stamp
    if os.path.exists(nic_log_folder):
        os.rmdir(nic_log_folder)
        os.mkdir(nic_log_folder)
    else:
        os.mkdir(nic_log_folder)
    local.path(nic_log_folder + "/vsperf_log_folder.txt").write(nic_log_folder)
    os.environ.putenv("NIC_LOG_FOLDER",nic_log_folder)
    pass


def conf_checks():
    proc_cmdline_info = local.path("/proc/cmdline").read()
    if not "intel_iommu=on" in proc_cmdline_info:
        log("Iommu Enablement" "Please enable IOMMU mode in your grub config")
        return 1
    if bash.bash("tuned-adm active | grep cpu-partitioning").value() == '':
        log("Tuned-adm" "cpu-partitioning profile must be active")
        return 1
    if bash.bash(""" cat /proc/cmdline  | grep "nohz_full=[0-9]"  """).value() == '':
        log("Tuned Config" "Must set cores to isolate in tuned-adm profile")
        return 1
    return 0
    pass


def hugepage_checks():
    log("*** Checking Hugepage Config ***")
    run("sleep 1")
    if bash.bash("""cat /proc/meminfo | awk /Hugepagesize/ | awk /1048576/""").value() == '':
        log("Hugepage Check" "Please enable 1G Hugepages")
        return 1
    return 0


def check_env_var(str_name):
    if get_env(str_name) != None:
        return True
    else:
        return False


def config_file_checks():
    log("*** Checking Config File ***")
    run("sleep 1")
    with pushd(case_path):
        str_all_name = """
        NIC1
        NIC2
        PMD_CPU_1
        PMD_CPU_2
        PMD_CPU_3
        PMD_CPU_4
        VCPU1
        VCPU2
        VCPU3
        VCPU4
        VCPU5
        TRAFFICGEN_TREX_HOST_IP_ADDR
        TRAFFICGEN_TREX_PORT1
        TRAFFICGEN_TREX_PORT2
        TREX_URL
        """.split()
        for name in str_all_name:
            if False == check_env_var(name):
                log(f"Please set the config Var {name} in Perf-Verify.conf file")
                return 1
        return 0


def nic_card_check():
    log("Now Checking for NIC cards")
    nic1 = get_env("NIC1")
    nic2 = get_env("NIC2")
    if local.path("/sys/class/net/" + nic1).exists == False or local.path("/sys/class/net/" + nic2).exists == False:
        log("NIC $NIC1 or NIC $NIC2 cannot be seen by kernel")
        return 1
    return 0


def rpm_check():
    log("*** Checking for installed RPMS ***")
    if bash("rpm -qa | grep ^openvswitch-[0-9]") == '':
        log("Openvswitch rpm" "Please install Openvswitch rpm")
        return 1
    if bash("rpm -qa | grep dpdk-tools") == "":
        log("Please install dpdk tools rpm ")
        return 1
    if bash("rpm -qa | grep dpdk-[0-9]") == "":
        log("Please install dpdk package rpm ")
        return 1
    if bash("rpm -qa | grep qemu-kvm-rhev") == "":
        log("Please install qemu-img-rhev rpm")
        return 1
    if bash("rpm -qa | grep qemu-kvm-tools-rhev") == "":
        log("Please install qemu-kvm-tools-rhev rpm ")
        return 1
    if bash("rpm -qa | grep qemu-kvm-tools-rhev") == "":
        log("Please install qemu-kvm-tools-rhev rpm ")
        return 1
    if bash("rpm -qa | grep qemu-img") == "":
        log("Please install qemu-img rpm ")
        return 1
    if bash("rpm -qa | grep qemu-kvm") == "":
        log("Please install qemu-kmv rpm ")
        return 1
    return 0


def network_connection_check():
    log("*** Checking connection to people.redhat.com ***")
    if bash("ping -c 1 people.redhat.com &> /dev/null"):
        log("*** Connection to server succesful ***")
    else:
        log("People.redhat.com connection fail" "!!! Cannot connect to people.redhat.com, please verify internet connection !!!")
        return 1
    return 0


def ovs_running_check():
    log("*** Checking for running instance of Openvswitch ***")
    if bash("pgrep ovs-vswitchd || pgrep ovsdb-server"):
        log("It appears Openvswitch may be running, please stop all services and processes")
    return 0


def download_VNF_image():
    with pushd(case_path):
        one_queue_image = get_env("one_queue_image")
        two_queue_image = get_env("two_queue_image")
        if os.path.exists(f"./{one_queue_image}"):
            pass
        else:
            log_info = """
            ***********************************************************************
            *** Downloading and decompressing VNF image. This may take a while! ***
            ***********************************************************************
            """
            log(log_info)
            one_queue_zip = get_env("one_queue_zip")
            bash(f"wget people.redhat.com/ctrautma/{one_queue_zip}")
            bash(f"lrzip -d {one_queue_zip}")
            bash(f"rm -f {one_queue_zip}")
        if os.path.exists(f"./{two_queue_image}"):
            pass
        else:
            log_info = """
            ***********************************************************************
            *** Downloading and decompressing VNF image. This may take a while! ***
            ***********************************************************************
            """
            log(log_info)
            two_queue_zip = get_env("two_queue_zip")
            bash(f"wget people.redhat.com/ctrautma/{two_queue_zip}")
            bash(f"lrzip -d {two_queue_zip}")
            bash(f"rm -f {two_queue_zip}")

        udev_file = "60-persistent-net.rules"
        data = """
        ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:03:00.0", NAME:="eth1"
        ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:04:00.0", NAME:="eth2"
        """
        local.path(udev_file).write(data)

    bash(
        f"virt-copy-in -a {case_path}/{one_queue_image} {udev_file} /etc/udev/rules.d/")
    bash(
        f"virt-copy-in -a {case_path}/{two_queue_image} {udev_file} /etc/udev/rules.d/")
    pass


def install_rpms():
    with pushd(case_path):
        all_package = """
        yum-utils
        scl-utils
        python36
        python36-devel
        python-netifaces
        python3-pyelftools
        wget
        nano
        ftp
        git
        tuna
        openssl
        sysstat
        libvirt
        libvirt-devel
        virt-install
        virt-manager
        virt-viewer
        czmq-devel
        libguestfs-tools
        ethtool
        vim
        lrzip
        libnl3-devel
        """.split()
        for pack in all_package:
            check_install(pack)
        bash("systemctl restart libvirtd")
    pass


def ovs_bridge_with_kernel(nic1_mac, nic2_mac, pmd_cpu_mask):
    cmd = f"""
	modprobe openvswitch
	systemctl stop openvswitch
	sleep 3
	systemctl start openvswitch
	sleep 3
	ovs-vsctl --if-exists del-br ovsbr0
	sleep 5

	ovs-vsctl set Open_vSwitch . other_config={{}}
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="4096,4096"
	ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask="{pmd_cpu_mask}"
    ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
	systemctl restart openvswitch
	sleep 3
	ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev

    ovs-vsctl add-port ovsbr0 dpdk0 -- set Interface dpdk0 type=dpdk options:dpdk-devargs="class=eth,mac={nic1_mac}"
    ovs-vsctl add-port ovsbr0 dpdk1 -- set Interface dpdk1 type=dpdk options:dpdk-devargs="class=eth,mac={nic2_mac}"

    # ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost0
    # ovs-vsctl add-port ovsbr0 vhost1 -- set interface vhost1 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost1

	ovs-ofctl del-flows ovsbr0
	ovs-ofctl add-flow ovsbr0 actions=NORMAL

	sleep 2
	ovs-vsctl show
    """
    run(cmd)


def ovs_bridge_with_dpdk(nic1_mac, nic2_mac, mtu_val, pmd_cpu_mask):
    cmd = f"""
	modprobe openvswitch
	systemctl stop openvswitch
	sleep 3
	systemctl start openvswitch
	sleep 3
	ovs-vsctl --if-exists del-br ovsbr0
	sleep 5

	ovs-vsctl set Open_vSwitch . other_config={{}}
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="4096,4096"
	ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask="{pmd_cpu_mask}"
    ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
	systemctl restart openvswitch
	sleep 3
	ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev

    ovs-vsctl add-port ovsbr0 dpdk0 -- set Interface dpdk0 type=dpdk options:dpdk-devargs="class=eth,mac={nic1_mac}" mtu_request={mtu_val}
    ovs-vsctl add-port ovsbr0 dpdk1 -- set Interface dpdk1 type=dpdk options:dpdk-devargs="class=eth,mac={nic2_mac}" mtu_request={mtu_val}

    ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost0
    ovs-vsctl add-port ovsbr0 vhost1 -- set interface vhost1 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost1

	ovs-ofctl del-flows ovsbr0
	ovs-ofctl add-flow ovsbr0 actions=NORMAL

	sleep 2
	ovs-vsctl show
    """
    run(cmd)


def vcpupin_in_xml(numa_node, template_xml, new_xml, cpu_list):
    with pushd(case_path):
        config_file_checks()
        local.path(template_xml).copy(new_xml)
        xml_tool.xml_add_vcpupin_item(new_xml, len(cpu_list))
        xml_tool.update_numa(numa_node)
        for i in range(len(cpu_list)):
            xml_tool.update_vcpu(new_xml, i, cpu_list[i])
    pass


def start_guest(guest_xml):
    with pushd(case_path):
        run("systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd")
        download_VNF_image()
        cmd = f"""
        virsh define {case_path}/{guest_xml}
        virsh start gg
        """
        run(cmd)


def destroy_guest():
    cmd = """
    virsh destroy gg
    virsh undefine gg
    """
    run(cmd)
    pass


def configure_guest():
    cmd = """
        stty rows 24 cols 120
        nmcli dev set eth1 managed no
        nmcli dev set eth2 managed no
        systemctl stop firewalld
        iptables -t filter -P INPUT ACCEPT
        iptables -t filter -P FORWARD ACCEPT
        iptables -t filter -P OUTPUT ACCEPT
        iptables -t mangle -P PREROUTING ACCEPT
        iptables -t mangle -P INPUT ACCEPT
        iptables -t mangle -P FORWARD ACCEPT
        iptables -t mangle -P OUTPUT ACCEPT
        iptables -t mangle -P POSTROUTING ACCEPT
        iptables -t nat -P PREROUTING ACCEPT
        iptables -t nat -P INPUT ACCEPT
        iptables -t nat -P OUTPUT ACCEPT
        iptables -t nat -P POSTROUTING ACCEPT
        iptables -t filter -F
        iptables -t filter -X
        iptables -t mangle -F
        iptables -t mangle -X
        iptables -t nat -F
        iptables -t nat -X
        ip6tables -t filter -P INPUT ACCEPT
        ip6tables -t filter -P FORWARD ACCEPT
        ip6tables -t filter -P OUTPUT ACCEPT
        ip6tables -t mangle -P PREROUTING ACCEPT
        ip6tables -t mangle -P INPUT ACCEPT
        ip6tables -t mangle -P FORWARD ACCEPT
        ip6tables -t mangle -P OUTPUT ACCEPT
        ip6tables -t mangle -P POSTROUTING ACCEPT
        ip6tables -t nat -P PREROUTING ACCEPT
        ip6tables -t nat -P INPUT ACCEPT
        ip6tables -t nat -P OUTPUT ACCEPT
        ip6tables -t nat -P POSTROUTING ACCEPT
        ip6tables -t filter -F
        ip6tables -t filter -X
        ip6tables -t mangle -F
        ip6tables -t mangle -X
        ip6tables -t nat -F
        ip6tables -t nat -X
        ip -d addr show
    """
    pts = bash("virsh ttyconsole gg").value()
    my_tool.run_cmd_get_output(pts, cmd)
    pass


# {modprobe  vfio enable_unsafe_noiommu_mode=1}
def guest_start_testpmd(queue_num, cpu_list, rxd_size, txd_size):
    dpdk_ver = get_env("dpdk_ver")
    cmd = f"""
    /root/one_gig_hugepages.sh 1
    rpm -ivh  /root/{dpdk_ver}/dpdk*.rpm
    modprobe -r vfio_iommu_type1
    modprobe -r vfio
    modprobe  vfio
    modprobe vfio-pci
    ip link set eth1 down
    ip link set eth2 down
    dpdk-devbind -b vfio-pci 0000:03:00.0
    dpdk-devbind -b vfio-pci 0000:04:00.0
    dpdk-devbind --status
    """
    pts = bash("virsh ttyconsole gg").value()
    my_tool.run_cmd_get_output(pts, cmd)

    num_core = 2
    if queue_num == 1:
        num_core = 2
    else:
        num_core = 4

    hw_vlan_flag = "--disable-hw-vlan"
    legacy_mem = ""

    cmd_test = f"""testpmd -l {cpu_list}  \
    --socket-mem 1024 \
    {legacy_mem} \
    -n 4 \
    -- \
    --forward-mode=io \
    --port-topology=pair \
    {hw_vlan_flag} \
    --disable-rss \
    -i \
    --rxq={queue_num} \
    --txq={queue_num} \
    --rxd={rxd_size} \
    --txd={txd_size} \
    --nb-cores={num_core} \
    --auto-start"
    """
    my_tool.run_cmd_get_output(pts,cmd,"testpmd>")
    pass

def clear_dpdk_interface():
    bus_list = bash(r"dpdk-devbind - s | grep - E drv = vfio-pci\| drv = igb | awk '{print $1}'").value()
    for bus in list(bus_list):
        kernel_driver = bash(f"lspci - s {bus} - v | grep Kernel | grep modules | awk '{{print $NF}}'").value()
        bash(f"dpdk-devbind - b {kernel_driver} {bus}")
    pass

def clear_env():
    cmd = """
    systemctl start openvswitch
    ovs-vsctl - -if-exists del-br ovsbr0
    virsh destroy gg
    virsh undefine gg
    systemctl stop openvswitch
    """
    run(cmd)
    clear_dpdk_interface()
    clear_hugepage()
    return 0

def bonding_test_trex(t_time,pkt_size):
    trex_server_ip = get_env("TRAFFICGEN_TREX_HOST_IP_ADDR")
    with pushd(case_path):
        ret = bash(f"ping {trex_server_ip} -c 3")
        if ret.code != 0:
            log("Trex server {} not up please check ".format(trex_server_ip))
        
        trex_url = "http://netqe-bj.usersys.redhat.com/share/wanghekai/v2.49.tar.gz"
        trex_dir = os.path.basename(trex_url).replace(".tar.gz","")
        trex_name = os.path.basename(trex_url)
        if not os.path.exists(trex_dir):
            run(f"wget {trex_url} > /dev/null 2>&1")
            run(f"tar -xvf {trex_name} > /dev/null 2>&1")
        log(f"python ./trex_sport.py -c {trex_server_ip} -t {t_time} --pkt_size={pkt_size} -m 10")
        run(f"python ./trex_sport.py - c {trex_server_ip} - t {t_time} - -pkt_size={pkt_size} -m 10")
    pass

def update_xml_sriov_vf_port(xml_file,vlan_id=0):
    
    vf1_bus_info = my_tool.get_bus_from_name(get_env("NIC1_VF"))
    vf2_bus_info = my_tool.get_bus_from_name(get_env("NIC2_VF"))
    vf1_bus_info.replace(":",'_')
    vf2_bus_info.replace(":",'_')
    
    vf1_domain = vf1_bus_info.split('_')[0]
    vf1_bus    = vf1_bus_info.split('_')[1]
    vf1_slot   = vf1_bus_info.split('_')[2]
    vf1_func   = vf1_bus_info.split('_')[3]

    vf2_domain = vf2_bus_info.split('_')[0]
    vf2_bus    = vf2_bus_info.split('_')[1]
    vf2_slot   = vf2_bus_info.split('_')[2]
    vf2_func   = vf2_bus_info.split('_')[3]

    vlan_item = """
    <interface type='hostdev' managed='yes'>
        <mac address={}/>
        <vlan >
            <tag id='{}'/>
        </vlan>
        <driver name='vfio'/>
        <source >
            <address type='pci' domain={} bus={} slot={} function={}/>
        </source >
        <address type='pci' domain={} bus={} slot={} function={}/>
    </interface >
    """
    item = """
    <interface type='hostdev' managed='yes'>
        <mac address={}/>
        <vlan >
            <tag id='{}'/>
        </vlan >
        <driver name='vfio'/>
        <source >
            <address type='pci' domain={} bus={} slot={} function={}/>
        </source >
        <address type='pci' domain={} bus={} slot={} function={}/>
    </interface >
    """

    xml_tool.remove_item_from_xml(xml_file,"./devices/interface[@type='hostdev']")

    if vlan_id != 0:
        vf1_format_list = ['52:54:00:11:8f:ea', vlan_id ,vf1_domain ,vf1_bus, vf1_slot, vf1_func, '0x0000', '0x03', '0x0', '0x0'] 
        vf1_vlan_item = vlan_item.format(*vf1_format_list)
        xml_tool.add_item_from_xml(xml_file,"./devices",vf1_vlan_item)

        vf2_format_list = ['52:54:00:11:8f:eb', vlan_id, vf2_domain, vf2_bus, vf2_slot, vf2_func, '0x0000', '0x04', '0x0', '0x0']
        vf2_vlan_item = vlan_item.format(*vf2_format_list)
        xml_tool.add_item_from_xml(xml_file,"./devices" ,vf2_vlan_item)
    else:
        vf1_format_list = ['52:54:00:11:8f:ea' ,vf1_domain, vf1_bus, vf1_slot, vf1_func, '0x0000', '0x03', '0x0', '0x0'] 
        vf1_vlan_item = vlan_item.format(*vf1_format_list)
        xml_tool.add_item_from_xml(xml_file,"./devices",vf1_vlan_item)

        vf2_format_list = ['52:54:00:11:8f:eb' ,vf2_domain ,vf2_bus, vf2_slot ,vf2_func, '0x0000', '0x04', '0x0', '0x0']
        vf2_vlan_item = vlan_item.format(*vf2_format_list)
        xml_tool.add_item_from_xml(xml_file,"./devices", vf2_vlan_item)
    pass


def update_xml_vnet_port(xml_file):
    append_item = """
        <interface type="bridge">
            <mac address="52:54:00:bb:63:7b" />
            <source bridge="virbr0" />
            <model type="virtio" />
            <address bus="0x02" domain="0x0000" function="0x0" slot="0x00" type="pci" />
        </interface>
    """

    item = """
        <interface type='bridge'>
            <mac address={}/>
            <source bridge={}/>
            <virtualport type='openvswitch'/>
            <address type='pci' domain={} bus={} slot={} function={}/>
            <target dev={}/>
            <model type='virtio'/>
        </interface>
    """
    xml_tool.remove_item_from_xml(xml_file,"./devices/interface[@type='bridge']")
    xml_tool.add_item_from_xml(xml_file,"./devices", append_item)

    
    vnet_format_list_one = ['52:54:00:11:8f:ea' 'ovsbr0' '0x0000' '0x03' '0x0' '0x0' 'vnet0']
    vnet_format_item_one = item.format(*vnet_format_list_one)
    xml_tool.add_item_from_xml(xml_file,"./devices" ,vnet_format_item_one)

    vnet_format_list_two = ['52:54:00:11:8f:eb' 'ovsbr0' '0x0000' '0x04' '0x0' '0x0' 'vnet1']
    vnet_format_item_two = item.format(*vnet_format_list_two)
    xml_tool.add_item_from_xml(xml_file,vnet_format_item_two)
    pass


def update_xml_vhostuser(xml_file):
    xml_tool.remove_item_from_xml(xml_file,"./devices/interface[@type='vhostuser']")
    item = """
        <interface type='vhostuser'>
            <mac address={}'/>
            <source type='unix' path={} mode='server'/>
            <model type='virtio'/>
            <driver name='vhost' iommu='on' ats='on'/>
            <address type='pci' domain={} bus={} slot={} function={}/>
        </interface>
    """
    f_list_one = ['52:54:00:11:8f:ea' '/tmp/vhost0' '0x0000' '0x03' '0x0' '0x0']
    f_item_one = item.format(*f_list_one)
    xml_tool.add_item_from_xml(xml_file,"./devices",f_item_one)

    f_list_two = ['52:54:00:11:8f:eb' '/tmp/vhost1' '0x0000' '0x04' '0x0' '0x0']
    f_item_two = item.format(*f_list_two)
    xml_tool.add_item_from_xml(xml_file,"./devices",f_item_two)
    pass

def ovs_dpdk_pvp_test(q_num,mtu_val,pkt_size,cont_time):
    clear_env()
    nic1_name = get_env("NIC1")
    nic2_name = get_env("NIC2")
    nic1_mac = my_tool.get_mac_from_name(nic1_name)
    nic2_mac = my_tool.get_mac_from_name(nic2_name)
    enable_dpdk(nic1_mac,nic2_mac)

    numa_node = bash("cat /sys/class/net/{nic1_name}/device/numa_node").value()
    vcpu1 = get_env("VCPU1")
    vcpu2 = get_env("VCPU2")

    if q_num == 1:
        vcpu_list = [get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3")]
        ovs_bridge_with_dpdk(nic1_mac,nic2_mac,mtu_val,get_env("PMD2MASK"))
    else:
        vcpu_list = [get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3"),get_env("VCPU4"),get_env("VCPU5")]
        ovs_bridge_with_dpdk(nic1_mac,nic2_mac,mtu_val,get_env("PMD4MASK"))
    new_xml = "g1.xml"
    vcpupin_in_xml(numa_node,"guest.xml",new_xml,vcpu_list)
    update_xml_vhostuser(new_xml)

    if q_num == 1:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("one_queue_image"))
    else:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("two_queue_image"))
    
    start_guest(new_xml)
    configure_guest()
    guest_start_testpmd(q_num,vcpu_list,get_env("RXD_SIZE"),get_env("TXD_SIZE"))
    bonding_test_trex(cont_time,pkt_size)
    pass

def ovs_kernel_datapath_test(q_num,pkt_size,cont_time):
    clear_env()
    
    nic1_name = get_env("NIC1")
    nic2_name = get_env("NIC2")
    nic1_mac = my_tool.get_mac_from_name(nic1_name)
    nic2_mac = my_tool.get_mac_from_name(nic2_name)
    enable_dpdk(nic1_mac,nic2_mac)

    numa_node = bash("cat /sys/class/net/{nic1_name}/device/numa_node").value()

    if q_num == 1:
        vcpu_list = [ get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3")]
        ovs_bridge_with_kernel(nic1_mac,nic2_mac,pkt_size,get_env("PMD2MASK"))
    else:
        vcpu_list = [ get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3"),get_env("VCPU4"),get_env("VCPU5")]
        ovs_bridge_with_kernel(nic1_mac,nic2_mac,pkt_size,get_env("PMD4MASK"))
        pass
    new_xml = "g1.xml"
    vcpupin_in_xml(numa_node,"guest.xml",new_xml,vcpu_list)
 
    update_xml_vnet_port(new_xml)

    if q_num == 1:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("one_queue_image"))
    else:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("two_queue_image"))
    start_guest(new_xml)
    configure_guest()
    guest_start_testpmd(q_num,vcpu_list,get_env("RXD_SIZE"),get_env("TXD_SIZE"))
    bonding_test_trex(cont_time,pkt_size)
    pass

def sriov_pci_passthrough_test(q_num,pkt_size,cont_time):
    clear_env()
    numa_node = bash("cat /sys/class/net/{}/device/numa_node".format(get_env("NIC1_VF"))).value()
    vcpu_list = [ get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3")]
    if q_num != 1:
        vcpu_list = [ get_env("VCPU1"),get_env("VCPU2"),get_env("VCPU3"),get_env("VCPU4"),get_env("VCPU5")]
    new_xml = "g1.xml"
    vcpupin_in_xml(numa_node,"guest.xml",new_xml,vcpu_list)
    update_xml_sriov_vf_port(new_xml,0)

    if q_num == 1:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("one_queue_image"))
    else:
        xml_tool.update_image_source(new_xml,case_path + "/" + get_env("two_queue_image"))
    start_guest(new_xml)
    configure_guest
    guest_start_testpmd(q_num,vcpu_list,get_env("SRIOV_RXD_SIZE"),get_env("SRIOV_TXD_SIZE"))
    bonding_test_trex(cont_time,pkt_size)
    pass


def run_tests(test_list):

    if test_list == "pvp_cont":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_cont.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            *************************************************************
            *** Running 1500 Byte PVP verify check ***
            *** For 1Q 2PMD Test
            *************************************************************
            """
            sys.stdout.write(data)
            ovs_dpdk_pvp_test(1,1500,1500,30)

    if test_list == "ALL" or test_list == "1Q":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_1Q.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            *************************************************************
            *** Running 1500 Byte PVP verify check ***
            *** For 1Q 2PMD Test
            *************************************************************
            """
            sys.stdout.write(data)
            ovs_dpdk_pvp_test(1,64,64,30)
            ovs_dpdk_pvp_test(1,1500,1500,30)

    if test_list == "ALL" or test_list == "2Q":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_2Q.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            *************************************************************
            *** Running 1500 Byte PVP verify check ***
            *** For 2Q 4PMD Test ***
            *************************************************************
            """
            sys.stdout.write(data)
            ovs_dpdk_pvp_test(2,64,64,30)
            ovs_dpdk_pvp_test(2,1500,1500,30)

    if test_list == "ALL" or test_list == "Jumbo":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_Jumbo.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            *************************************************************
            *** Running 2000/9000 Bytes 2PMD PVP OVS/DPDK VSPerf TEST ***
            *************************************************************
            """
            sys.stdout.write(data)
            ovs_dpdk_pvp_test(1,2000,2000,30)
            ovs_dpdk_pvp_test(2,9000,9000,30)

    if test_list == "ALL" or test_list == "Kernel":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_kernel.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            ************************************************************
            *** Running 64/1500 Bytes PVP OVS Kernel VSPerf TEST ***
            ************************************************************
            """
            sys.stdout.write(data)
            ovs_kernel_datapath_test(1,64,30)
            ovs_kernel_datapath_test(2,1500,30)
    
    if test_list == "ALL" or test_list == "SRIOV":
        log_file = get_env("NIC_LOG_FOLDER") + "/" + "pvp_sriov.log"
        with outtee(log_file,buff=1),errtee(log_file,buff=1):
            data = """
            ************************************************
            *** Running 64/1500 Bytes SR-IOV VSPerf TEST ***
            ************************************************
            """
            sys.stdout.write(data)
            ovs_kernel_datapath_test(1,64,30)
            ovs_kernel_datapath_test(2,1500,30)

    pass



def copy_config_files_to_log_folder():
    log_folder = get_env("NIC_LOG_FOLDER")
    bash("cp /root/RHEL_NIC_QUALIFICATION/Perf-Verify.conf {}".format(log_folder))
    pass

def usage():
    data = """
    Usage: $progname[-t test to execute][-h print help]
    -t tests to execute['1Q, 2Q, Jumbo, Kernel, pvp_cont', 'SRIOV'] default is to run all tests
    -h print this help message
    """
    print(data)
    pass

def main(test_list="ALL"):
    # run all checks
    os_check()
    log_folder_check()
    hugepage_checks()
    conf_checks()
    config_file_checks()
    nic_card_check()
    rpm_check()
    network_connection_check()
    ovs_running_check()
    # finished running checks
    run_tests(test_list)
    copy_config_files_to_log_folder()
    pass

if __name__ == "__main__":
    send_command("rlJournalStart")
    main()
    send_command("rlJournalPrintText")
    send_command("rlJournalEnd")
    pass