#!/usr/bin/env python3

import os
import contextlib
import sys
import pprint
import platform as pl
import shutil as sh
import subprocess as sp
import base64
import time

from envbash import load_envbash
from plumbum import local
from functools import wraps
from bash import bash

sys.path.append(os.getcwd() + "/../")
sys.path.append(os.getcwd() + "/../common/")
import bond.tools as tools
import bond.xmltool as xmltool

from common.lib_sriov import LIB_SRIOV as pysriov
case_path = os.environ.get("CASE_PATH")
system_version_id = int(os.environ.get("SYSTEM_VERSION_ID"))
my_tool = tools.Tools()
xml_tool = xmltool.XmlTool()
fd_nic_pipe = os.environ.get("fd_nic_pipe")
notify_pipe = os.environ.get("notify_pipe")

def set_check(ret):
    def my_wrap(f):
        @wraps(f)
        def log_f_as_called(*args, **kwargs):
            cur_time = time.asctime()
            my_command = f'{f.__name__} {args} {kwargs}'
            cmd = f""":: [  BEGIN   ] :: Running '{my_command}'"""
            log(cmd)
            value = f(*args, **kwargs)
            cur_time = time.asctime()
            cmd = f""":: [  END   ] :: Running '{my_command}' RETURN {value}"""
            log(cmd)
            return value
        return log_f_as_called
    return my_wrap    

def send_command(cmd):
    cmd = cmd + os.linesep
    try:
        with open(notify_pipe,"r") as rfd:
            rfd.read()
            with open(fd_nic_pipe,"w") as fd:
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
    cmds = [ i.strip() for i in cmds ]
    for cmd in cmds:
        if len(cmd) > 0:
            sh_run(cmd, str_ret_val)
    pass

def runlog(cmd, str_ret_val="0"):
    cmds = cmd.split('\n')
    cmds = [ i.strip() for i in cmds ]
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


@set_check(0)
def main():
    print(sys.path)
    log(sys.path)
    load_envbash(os.getcwd() + "/env.sh")


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
    try:
        yield
    finally:
        send_command("rlPhaseEnd")


def check_install(pkg_name):
    run("rpm -q {} || yum -y install {}".format(pkg_name, pkg_name))


def install_init_package():
    all_packs = "wget git gcc make bc lsof nmap-ncat tcpdump expect ethtool yum-utils".split()
    for pack in all_packs:
        check_install(pack)
    if system_version_id < 80:
        check_install("bridge-utils")
    pass


def add_epel_repo():
    if system_version_id < 80:
        run("rpm -q epel-release || yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm")
    else:
        run("rpm -q epel-release || dnf -y install epel-release")
    pass


@set_check(0)
def install_package():
    add_epel_repo()
    if system_version_id < 80:
        check_install("qemu-img-rhev")
        check_install("qemu-kvm-common-rhev")
        check_install("qemu-kvm-rhev")
        check_install("qemu-kvm-tools-rhev")
    else:
        check_install("qemu-img")
        check_install("qemu-kvm")
        check_install("platform-python-devel")
    all_pack = """
        lrzip
        tcpdump
        python36
        ethtool
        yum-utils
        scl-utils
        libnl3-devel
        python36-devel
        wget
        nano
        ftp
        git
        tuna
        openssl
        sysstat
        tuned-profiles-cpu-partitioning
        libvirt
        libvirt-devel
        virt-install
        virt-manager
        virt-viewer
        czmq-devel
        libguestfs-tools
        ethtool
        libvirt-devel
        emacs
        gcc
        git
        lshw
        pciutils
        """.split()

    for pack in all_pack:
        check_install(pack)

    # for qemu bug that can not start qemu
    if system_version_id < 80:
        local.path("/etc/libvirt/qemu.conf").write("group = 'hugetlbfs'", mode="a+")

    run("systemctl restart libvirtd")
    run("systemctl start virtlogd.socket")

    # work around for failure of virt-install
    run("chmod 666 /dev/kvm")
    pass


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
def config_isolated_cpu_and_Gb_hugepage(str_cpus, num_hpage):
    run("rpm -q grubby || yum -y install grubby")
    run("rpm -qa | grep tuned-profiles-cpu-partitioning || yum -y install tuned-profiles-cpu-partitioning")
    local.path("/etc/tuned/cpu-partitioning-variables.conf").write("isolated_cores={}".format(str_cpus))
    run("tuned-adm profile cpu-partitioning")

    default_kernel = bash("grubby --default-kernel").value()
    cmd_line = f"""
    grubby --args='nohz=on default_hugepagesz=1G hugepagesz=1G \
    hugepages={num_hpage} intel_iommu=on iommu=pt \
    modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr' \
    --update-kernel {default_kernel}\
    """
    run(cmd_line)
    pass


@set_check(0)
def add_yum_profiles():
    if system_version_id < 80:
        epel_url = "http://download.lab.bos.redhat.com/rcm-guest/puddles/OpenStack/rhos-release/rhos-release-latest.noarch.rpm"
        run(f"rpm -q rhos-release || yum -y install {epel_url}")
        if not os.path.exists("/etc/yum.repos.d/rhos-release-13.repo"):
            with pushd(case_path):
                sh.copy("rhos-release-13.repo", "/etc/yum.repos.d/")

        run("rpm --import 'http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF'")
        data = """
        [tuned]
        name=Tuned development repository for RHEL-7
        baseurl=https://fedorapeople.org/~jskarvad/tuned/devel/repo/
        enabled=1
        gpgcheck=0
        skip_if_unavailable=1
        [mono-repo]
        name=mono-repo
        baseurl=http://download.mono-project.com/repo/centos/
        enabled=1
        gpgcheck=0
        skip_if_unavailable=1
        """
        data = "".join([i.strip() + '\n' for i in data.split('\n') if i != ''])
        local.path("/etc/yum.repos.d/tuned.repo").write(data, mode="w")


@set_check(0)
def install_ovs():
    ovs_version = os.environ.get("OVS_URL")
    pack_name = os.path.basename(ovs_version)[:-4]
    container_selinux_url = os.environ.get("CONTAINER_SELINUX_URL")
    ovs_selinux_url = os.environ.get("OVS_SELINUX_URL")
    ovs_url = os.environ.get("OVS_URL")
    run(f"yum -y install {container_selinux_url} {ovs_selinux_url} {ovs_url}", "0,1")


@set_check(0)
def install_driverctl():
    driverctl_url = os.environ.get("DRIVERCTL_URL")
    run(f"rpm -qa | grep `basename -s '.rpm' {driverctl_url}` || yum install -y {driverctl_url}")


@set_check(0)
def install_dpdk():
    dpdk_url = os.environ.get("DPDK_URL")
    dpdk_tool_url = os.environ.get("DPDK_TOOL_URL")
    run(f"rpm -qa | grep `basename -s '.rpm' {dpdk_url}` || rpm -ivh {dpdk_url}")
    run(f"rpm -qa | grep `basename -s '.rpm' {dpdk_tool_url}` || rpm -ivh {dpdk_tool_url}")


@set_check(0)
def init_netscout_tool():
    netscout_url = "https://github.com/ctrautma/NetScout.git"
    dir_name = os.path.basename(netscout_url).split(".")[0]
    if not os.path.exists(dir_name):
        run(f"git clone {netscout_url}")
        with pushd(f"{case_path}/{dir_name}"):
            run("git checkout bddc7bdf5a4fc9cfb9cd73f2cfc0d731af6b0bd1")
            run("chmod 777 NSConnect.py")


@set_check(0)
def scout_connect(port1, port2):
    dir_name = f"""{case_path}/NetScout"""
    with pushd(dir_name):
        log(f"NETSCOUT CONNECT PORT {port1} AND {port2}")
        if system_version_id < 80:
            run(f"python3 NSConnect.py --connect {port1} {port2}")
        else:
            run(f"python36 NSConnect.py --connect {port1} {port2}")


@set_check(0)
def scout_disconnect(port1, port2):
    dir_name = f"""{case_path}/NetScout"""
    with pushd(dir_name):
        log(f"NETSCOUT DISCONNECT PORT {port1} AND {port2}")
        if system_version_id < 80:
            run(f"python3 NSConnect.py --disconnect {port1} {port2}")
        else:
            run(f"python36 NSConnect.py --disconnect {port1} {port2}")


@set_check(0)
def scout_show():
    dir_name = f"""{case_path}/NetScout"""
    with pushd(dir_name):
        if system_version_id < 80:
            run("python3 NSConnect.py --showconnections")
        else:
            run("python36 NSConnect.py --showconnections")


@set_check(0)
def init_netscout_config():
    dir_name = f"""{case_path}/NetScout"""
    with pushd(dir_name):
        netscout_host = os.environ.get("NETSCOUT_HOST")
        if netscout_host != "":
            import base64
            #host_name = base64.standard_b64encode(bytes(netscout_host,"utf-8"))
            host_name = bash("echo {} | base64".format(netscout_host)).value()
            #print(host_name)
        else:
            host_name = 'YWRtaW5pc3RyYXRvcg=='

        config_info = f"""
        [INFO]
        password = bmV0c2NvdXQx
        username = YWRtaW5pc3RyYXRvcg==
        port = NTMwNTg=
        host = {host_name}
        """
        configs = config_info.split('\n')
        configs = [i.strip() for i in configs if len(i.strip()) > 0 ]
        config_info = "\n".join(configs)
        local.path(dir_name + '/' + "settings.cfg").write(config_info)


@set_check(0)
def init_physical_topo_without_switch():
    init_netscout_tool()
    init_netscout_config()
    server_port_one = os.environ.get("SERVER_PORT_ONE")
    client_port_one = os.environ.get("CLIENT_PORT_ONE")
    server_port_two = os.environ.get("SERVER_PORT_TWO")
    client_port_two = os.environ.get("CLIENT_PORT_TWO")
    if os.environ.get("CONN_TYPE") == "netscout":
        scout_connect(server_port_one, client_port_one)
        scout_connect(server_port_two, client_port_two)
    else:
        log("DO NOTHING,JUST FOR CUSTOMER PFT TEST")


@set_check(0)
def init_physical_topo_with_switch():
    init_netscout_tool()
    init_netscout_config()
    conn_type = os.environ.get("CONN_TYPE")
    switch_port_one = os.environ.get("SWITCH_PORT_ONE")
    switch_port_two = os.environ.get("SWITCH_PORT_TWO")
    switch_port_three = os.environ.get("SWITCH_PORT_THREE")
    switch_port_four = os.environ.get("SWITCH_PORT_FOUR")
    server_port_one = os.environ.get("SERVER_PORT_ONE")
    server_port_two = os.environ.get("SERVER_PORT_TWO")
    client_port_one = os.environ.get("CLIENT_PORT_ONE")
    client_port_two = os.environ.get("CLIENT_PORT_TWO")

    if conn_type == "netscout":
        if os.environ["TRAFFIC_TYPE"] == "xena":
            traffic_port_one = os.environ.get("TRAFFIC_PORT_ONE")
            traffic_port_two = os.environ.get("TRAFFIC_PORT_TWO")
            scout_connect(traffic_port_one, switch_port_three)
            scout_connect(traffic_port_two, switch_port_four)
            scout_connect(server_port_one, switch_port_one)
            scout_connect(server_port_two, switch_port_two)
        elif os.environ["TRAFFIC_TYPE"] == "trex":

            scout_connect(server_port_one, switch_port_one)
            scout_connect(server_port_two, switch_port_two)
            scout_connect(client_port_one, switch_port_three)
            scout_connect(client_port_two, switch_port_four)
        else:
            log("Do Nothing , Just for Customer Test")


def i_am_server():
    return os.environ["SERVERS"] == os.environ["HOSTNAME"]


def i_am_client():
    return os.environ["CLIENTS"] == os.environ["HOSTNAME"]


@set_check(0)
def config_hugepage():
    run("systemctl enable tuned && systemctl start tuned")
    if i_am_server():
        server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
        server_nic = my_tool.get_nic_name_from_mac(server_nic1_mac)
        server_cpu = get_isolate_cpus(server_nic)
        server_cpu = server_cpu.replace(" ", ",")
        config_isolated_cpu_and_Gb_hugepage(server_cpu, 24)
    elif i_am_client():
        client_nic1_mac = os.environ.get("CLIENT_NIC1_MAC")
        client_nic = my_tool.get_nic_name_from_mac(client_nic1_mac)
        client_cpu = get_isolate_cpus(client_nic)
        client_cpu = client_cpu.replace(" ", ",")
        config_isolated_cpu_and_Gb_hugepage(client_cpu, 24)
    else:
        log("Error Rule for config huge page")
    pass


@set_check(0)
def enable_dpdk(nic1_mac, nic2_mac):
    install_dpdk()
    install_driverctl()
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
        log("using dpdk-devbind.py set the vfio-pci driver to nic)
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

@set_check(0)
def enable_openvswitch_as_root_user():
    for i in ["nfp", "broadcom", "xxv"]:
        if os.environ["NIC_DRIVER"] == i:
            run("sed -ie 's/OVS_USER_ID/#OVS_USER_ID/g' /etc/sysconfig/openvswitch")
            break
    pass


@set_check(0)
def init_test_env():
    if i_am_server():
        server_nic1_name = get_nic_name_from_mac(os.environ["SERVER_NIC1_MAC"])
        os.environ["SERVER_NIC1_NAME"] = server_nic1_name
        os.environ["SERVER_NUMA"] = bash(
            f"cat /sys/class/net/{server_nic1_name}/device/numa_node").value()
        os.environ["ISOLCPUS_SERVER"] = get_isolate_cpus(server_nic1_name)
        os.environ["SERVER_PMD_CPU_MASK"] = get_pmd_masks(
            os.environ["ISOLCPUS_SERVER"])
    elif i_am_client():
        client_nic1_name = get_nic_name_from_mac(os.environ["CLIENT_NIC1_MAC"])
        os.environ["CLIENT_NIC1_NAME"] = client_nic1_name
        os.environ["CLIENT_NUMA"] = bash(
            f"cat /sys/class/net/{client_nic1_name}/device/numa_node").value()
        os.environ["ISOLCPUS_CLIENT"] = get_isolate_cpus(client_nic1_name)
        os.environ["CLIENT_PMD_CPU_MASK"] = get_pmd_masks(
            os.environ["ISOLCPUS_CLIENT"])
    else:
        log("error server role")
        pass

    if i_am_server():
        log(":::: SERVER NUMA IS {}".format(os.environ["SERVER_NUMA"]))
        log(":::: SERVER ISOLATED CPUS IS {}".format(
            os.environ["ISOLCPUS_SERVER"]))
        log(":::: SERVER PMD CPU MASK IS {}".format(
            os.environ["SERVER_PMD_CPU_MASK"]))
    else:
        log(":::: CLIENT NUMA IS {}".format(os.environ["CLIENT_NUMA"]))
        log(":::: CLIENT ISOLATED CPUS IS {}".format(
            os.environ["ISOLCPUS_CLIENT"]))
        log(":::: CLIENT PMD CPU MASK IS {}".format(
            os.environ["CLIENT_PMD_CPU_MASK"]))
    pass


@set_check(0)
def bonding_nic(nic1_mac, nic2_mac, bond_mode, mtu_val):
    # enable_openvswitch_as_root_user
    if i_am_server():
        pmd_cpu_mask = os.environ["SERVER_PMD_CPU_MASK"]
    elif i_am_client():
        pmd_cpu_mask = os.environ["CLIENT_PMD_CPU_MASK"]
    else:
        log("error server role")

    quote_str = '{}'
    cmd = f"""
    modprobe openvswitch
    systemctl stop openvswitch
    sleep 3
    systemctl start openvswitch
    sleep 3
    ovs-vsctl --if-exists del-br ovsbr0
    sleep 5
    ovs-vsctl set Open_vSwitch . other_config={quote_str}

    ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
    ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="4096,4096"
    ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask={pmd_cpu_mask}
    ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
    systemctl restart openvswitch
    sleep 3
    ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev

    ovs-vsctl add-bond ovsbr0 dpdkbond dpdk0 dpdk1 "bond_mode={bond_mode}" \
    -- set Interface dpdk0 type=dpdk options:dpdk-devargs=class=eth,mac={nic1_mac} mtu_request={mtu_val} \
    -- set Interface dpdk1 type=dpdk options:dpdk-devargs=class=eth,mac={nic2_mac} mtu_request={mtu_val}

    # set dpdkbond port with vlan mode trunk and permit all vlans
    ovs-vsctl set Port dpdkbond vlan_mode=trunk
    ovs-vsctl list Port dpdkbond

    # set updelay and downdelay for test
    ovs-vsctl set Port dpdkbond bond_updelay=5
    ovs-vsctl set Port dpdkbond bond_downdelay=5
    """
    run(cmd)

    cmd = """
    updelay=`ovs-vsctl list Port dpdkbond | grep bond_updelay | awk '{print $NF}'`
    downdelay=`ovs-vsctl list Port dpdkbond | grep bond_downdelay | awk '{print $NF}'`
    rlAssertEquals "Check bond up delay time " "$updelay" "5"
    rlAssertEquals "Check bond down delay time " "$downdelay" "5"
    ovs-vsctl list Port dpdkbond

    # ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuser
    ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost0
    # chmod 777 /var/run/openvswitch/vhost0

    ovs-ofctl del-flows ovsbr0
    ovs-ofctl add-flow ovsbr0 actions=NORMAL

    sleep 2
    ovs-vsctl show
    sleep 5
    echo "after bonding nic, check the bond status"
    ovs-appctl bond/show
    sleep 30
    ovs-appctl bond/show
    """
    run(cmd)

    pass


@set_check(0)
def start_libvirtd_service():
    run("systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd")


@set_check(0)
def start_guest(config_file="g1.xml"):
    start_libvirtd_service()
    img_guest = os.environ["IMG_GUEST"]

    image_name = os.path.basename(img_guest)
    if os.path.exists("/root/rhel.qcow2"):
        run("rm -f /root/rhel.qcow2")

    run(f"wget -P /root/ {img_guest} > /dev/null 2>&1")
    with pushd("/root/"):
        run(f"mv {image_name} rhel.qcow2")

    run("chmod 777 /root/")
    with pushd(case_path):
        udev_file = "60-persistent-net.rules"
        local.path(udev_file).touch()
        if i_am_server():
            data = """
            ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:11:8f:ea", NAME="eth1"
            ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:bb:63:7b", NAME="eth2"
            """
            local.path(udev_file).write(data)
        else:
            data = """
            ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:11:8f:eb", NAME="eth1"
            ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:bb:63:7b", NAME="eth2"
            """
            local.path(udev_file).write(data)
        run(
            f"virt-copy-in -a /root/rhel.qcow2 {udev_file} /etc/udev/rules.d/")

    guest_dpdk_version = os.environ["GUEST_DPDK_VERSION"]
    guest_dpdk_url = os.environ["GUEST_DPDK_URL"]
    guest_dpdk_tool_url = os.environ["GUEST_DPDK_TOOL_URL"]

    cmd = f"""
        rm -rf /root/{guest_dpdk_version}
        mkdir -p /root/{guest_dpdk_version}
        wget -P /root/{guest_dpdk_version}/ {guest_dpdk_url}      > /dev/null 2>&1
        wget -P /root/{guest_dpdk_version}/ {guest_dpdk_tool_url} > /dev/null 2>&1
        virt-copy-in -a /root/rhel.qcow2 /root/{guest_dpdk_version}/ /root/
        sleep 5
        virsh define {case_path}/{config_file}
        chmod 777 /root/
    """
    run(cmd)

    with pushd(case_path + "/"):
        g_name = xml_tool.xml_get_name(config_file)

    cmd = f"""
    virsh start {g_name}
    sleep 30
    """
    runlog(cmd)


@set_check(0)
def destroy_guest(name="guest30032"):
    cmd = f"""
    virsh destroy {name}
    virsh undefine {name}
    """
    run(cmd)


@set_check(0)
def configure_guest(guest_name,ip_addr):
    cmd = f"""
    test -d /sys/class/net/eth0 && nmcli dev set eth0 managed no
    test -d /sys/class/net/eth1 && nmcli dev set eth1 managed no
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
    dhclient -v eth2
    test -d /sys/class/net/eth0 && ip addr add {ip_addr}/24 dev eth0
    test -d /sys/class/net/eth1 && ip addr add {ip_addr}/24 dev eth1
    ip -d addr show
    """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    all_result = my_tool.run_cmd_get_output(pts, cmd)
    log(all_result)
    pass


@set_check(0)
def update_ssh_trust():
    cmd = """
    mkdir -p ~/.ssh
    rm -f ~/.ssh/*
    touch ~/.ssh/known_hosts
    chmod 644 ~/.ssh/known_hosts
    """
    run(cmd)
    trex_server_ip = os.environ["TREX_SERVER_IP"]
    trex_server_password = os.environ["TREX_SERVER_PASSWORD"]
    cmd = f"""
    ssh-keyscan $TREX_SERVER_IP >> ~/.ssh/known_hosts
    echo 'y\n' | ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
    python tools.py config-ssh-trust ~/.ssh/id_rsa.pub {trex_server_ip} root {trex_server_password}
    """
    run(cmd)


@set_check(0)
def clear_dpdk_interface():
    if bash("rpm -qa | grep dpdk-tools").value():
        bus_list = bash(
            "dpdk-devbind -s | grep  -E drv=vfio-pci\|drv=igb | awk '{print $1}'").value()
        for i in list(bus_list):
            kernel_driver = bash(
                "lspci -s {i} -v | grep Kernel  | grep modules  | awk '{print $NF}'".format(i)).value()
            run("dpdk-devbind -b {} {}".format(kernel_driver, i))
    pass


@set_check(0)
def clear_env():
    for i in local.path(case_path):
        if i.endswith("xml"):
            print(i)
            #import pdb; pdb.set_trace()
            name = xml_tool.xml_get_name(str(i))
            send_command(f"virsh destroy {name}")
            send_command(f"virsh undefine {name}")

    cmd = """
    modprobe -r bonding
    modprobe openvswitch
    systemctl start libvirtd
    systemctl start openvswitch
    ovs-vsctl --if-exists del-br ovsbr0
    systemctl restart libvirtd
    systemctl stop openvswitch
    """
    run(cmd,"0,1")

    clear_trex()
    clear_dpdk_interface()
    clear_hugepage()
    if i_am_server():
        nic1_mac = os.environ["SERVER_NIC1_MAC"]
        nic2_mac = os.environ["SERVER_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} down
        ip link set {nic2_name} down
        """
        run(cmd)
    elif i_am_client():
        nic1_mac = os.environ["CLIENT_NIC1_MAC"]
        nic2_mac = os.environ["CLIENT_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} down
        ip link set {nic2_name} down
        """
        run(cmd)
    else:
        log("Here wrong rule")
    pass


@set_check(0)
def ovs_tcpdump_install():
    python_ovs_url = os.environ["PYTHON_OVS_URL"]
    ovs_test_url = os.environ["OVS_TEST_URL"]
    cmd = f"""
    rpm -ivh {python_ovs_url} --nodeps
    rpm -ivh {ovs_test_url} --nodeps
    """
    run(cmd)


@set_check(0)
def update_beaker_tasks_repo():
    with pushd(case_path):
        with open("/etc/yum.repos.d/beaker-tasks.repo", mode="r+") as fd:
            all_data = fd.readlines()
            for i in range(0, len(all_data)):
                line = all_data[i]
                key = line.split("=")
                if "baseurl" in key:
                    all_data[i] = "baseurl=http://beaker.engineering.redhat.com/rpms\n"
                    break
            fd.seek(0)
            fd.truncate()
            log("".join(all_data))
            fd.write("".join(all_data))


@set_check(0)
def install_trex_and_start(nic1_mac, nic2_mac, trex_url):
    update_beaker_tasks_repo()
    with pushd(case_path):
        cmd = """
        yum -y clean all
        install_dpdk
        install_driverctl
        yum -y install emacs \
        gcc \
        git \
        lshw \
        pciutils \
        python-devel \
        python-setuptools \
        python-pip \
        tmux \
        tuned-profiles-cpu-partitioning \
        wget
        """
        run(cmd)

        trex_name = os.path.basename(trex_url)
        trex_dir = str(trex_name).split(".")[0]
        run(f"test -d {trex_dir} || wget {trex_dir} > /dev/null 2>&1")
        run(f"test -d {trex_dir} || tar -xvf {trex_name} > /dev/null 2>&1")
        with pushd("./{}".format(trex_dir)):
            nic1_name = get_nic_name_from_mac(nic1_mac)
            nic2_name = get_nic_name_from_mac(nic2_mac)
            nic1_bus = my_tool.get_bus_from_name(nic1_name)
            nic2_bus = my_tool.get_bus_from_name(nic2_name)
            nic_bus = nic1_bus + " " + nic2_bus
            run("rm -f /etc/trex_cfg.yaml")
            run(
                "./dpdk_setup_ports.py -c {} --force-macs --no-ht -o /etc/trex_cfg.yaml".format(nic_bus))
            run("systemctl enable tuned && systemctl start tuned")
            enable_dpdk(nic1_mac, nic2_mac)
            run("./trex_daemon_server restart")
    pass


@set_check(0)
def clear_hugepage():
    hugepage_dir = bash("mount -l | grep hugetlbfs | awk '{print $3}'").value()
    run(f"rm -rf {hugepage_dir}/*")
    return 0


@set_check(1)
def clear_trex():
    cmd = """
    pkill t-rex-64
    pkill t-rex-64
    pkill _t-rex-64
    pkill _t-rex-64
    echo
    """
    run(cmd,"0,1")
    pass


def clear_trex_and_free_hugepage():
    clear_trex()
    clear_hugepage()

# create vf from pf nic name with special num
@set_check(0)
def vf_create(pf, num):
    pf_bus = pysriov.sriov_get_pf_bus_from_pf_name(pf)
    pysriov.sriov_create_vfs(pf_bus[0], num)
    #for some nic create speed is low so here wait some time
    time.sleep(5)
    for i in range(0, num):
        run(f"ip li set {pf} vf {i} spoofchk off trust on")
    pass


@set_check(0)
def vf_mac_config(pf_name, vf_index, mac_addr):
    run(f"ip link set {pf_name} vf {vf_index} mac {mac_addr}")
    pass


@set_check(0)
def vf_mtu_change(vf_name, mtu_val):
    run(f"ip link set {vf_name} up")
    real_mtu = 1500
    if mtu_val <= 9200:
        real_mtu = mtu_val
    else:
        real_mtu = 9200
    run(f"ip link set {vf_name} mtu {mtu_val}")
    pass


@set_check(0)
def ovs_bond_config(bridge_name, bond_name, slaves, parameter):
    cmd = f"""
    ovs-vsctl add-bond {bridge_name} {bond_name} {slaves} {parameter}
    ovs-appctl bond/show
    """
    run(cmd)


@set_check(0)
def ovs_dpdk_bond_config(nic1_mac, nic2_mac, bond_mode, mtu):
    enable_dpdk(nic1_mac, nic2_mac)
    bonding_nic(nic1_mac, nic2_mac, bond_mode, mtu)
    pass


@set_check(0)
def add_bridge_interface_to_xml(br_name, mac_addr, bus_info):
    # <interface type="bridge">
    #   <source bridge="ovsbr0"/>
    #   <mac address="00:de:ad:01:01:08"/>
    #   <target dev="vnet0"/>
    #   <model type="virtio"/>
    #   <virtualport type="openvswitch"/>
    #   <address type="pci" domain="0" bus="4" slot="0" function="0"/>
    # </interface>
    with pushd(case_path):
        if os.path.exists("g1.xml"):
            result = bash("cat g1.xml | virt-xml --remove-device --network type=vhostuser").value()
            if result:
                local.path("./g1.xml").write(result)
            result = ""
            cmd1 = f"""cat g1.xml | virt-xml --add-device --network """
            cmd2 = f"""
            bridge={br_name},\
            mac={mac_addr},\
            model=virtio,\
            virtualport_type=openvswitch,\
            address.type=pci,\
            address.domain=0x0000,\
            address.bus={bus_info},\
            address.slot=0x0,\
            address.function=0x0
            """
            cmd = cmd1 + "".join(cmd2.split())
            log(cmd)
            result = bash(cmd).value()
            if result:
                local.path("./g1.xml").write(result)
        else:
            log("Can not find vm config file named g1.xml")
    pass

@set_check(0)
def add_vhostuser_interface_to_xml(mac_addr, target, bus_info, source_path, source_mode):
    # <interface type="vhostuser">
    #   <source type="unix" path="/tmp/vhost0" mode="server"/>
    #   <mac address="00:de:ad:01:01:08"/>
    #   <target dev="eth1"/>
    #   <model type="virtio"/>
    #   <address type="pci" domain="0" bus="16" slot="0" function="0"/>
    #   <driver name="vhost"/>
    # </interface>

    with pushd(case_path):
        if os.path.exists("g1.xml"):
            result = bash("cat g1.xml | virt-xml --remove-device --network type=vhostuser").value()
            if result:
                local.path("./g1.xml").write(result)
            cmd1 = f"""cat g1.xml | virt-xml --add-device --network """
            cmd2 = f"""
            type=vhostuser,\
            mac={mac_addr},\
            driver_name=vhost,\
            target={target},\
            model=virtio,\
            address.type=pci,\
            address.domain=0x0000,\
            address.bus={bus_info},\
            address.slot=0x0,\
            address.function=0x0,\
            source_type=unix,\
            source_path={source_path},\
            source_mode={source_mode}
            """
            cmd = cmd1 + "".join(cmd2.split())
            log(cmd)
            result = bash(cmd).value()
            if result:
                local.path("./g1.xml").write(result)
        else:
            log("Can not find g1.xml")
    pass


@set_check(0)
def connection_ping_check(guest_name,cmd):
    tty_console = bash(f"virsh ttyconsole {guest_name}").value()
    result = my_tool.run_cmd_get_output(tty_console, cmd)
    log(result)
    return result
    pass

# Test item
@set_check(0)
def ovs_linux_bond_functional_test(bond_mode):
    clear_env()
    guest_xml= "g1.xml"
    with pushd(case_path):
        send_command(f"test -f {guest_xml} && rm -f {guest_xml}")
        send_command(f"test -f {guest_xml} || cp guest.xml {guest_xml}")

    nic1_name = None
    nic2_name = None
    if i_am_server():
        with enter_phase("create vf and get vf name"):
            init_physical_topo_with_switch()
            server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
            server_nic2_mac = os.environ.get("SERVER_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(server_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(server_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            slaves = [vf1_name, vf2_name]

        with enter_phase("create linux bonding and add it to ovs "):
            br_name = "ovsbr0"
            bond_name = "bond0"
            bond_parameter = ""
            if bond_mode == "active-backup":
                bond_parameter = "miimon=100 mode=1"
            elif bond_mode == "balance-tcp":
                bond_parameter = "miimon=100 mode=4 lacp_rate=1"
            else:
                send_command(""" rlFail "invalid bond mode" """)

            cmd = f"""
            modprobe bonding {bond_parameter}
            ip link add name {bond_name} type bond
            ip link set dev {bond_name} up
            ip link set {vf1_name} up
            ip link set {vf2_name} up
            ifenslave {bond_name} {vf1_name}
            ifenslave {bond_name} {vf2_name}
            modprobe openvswitch
            systemctl stop openvswitch
            sleep 3
            systemctl start openvswitch
            sleep 3
            ovs-vsctl --if-exists del-br ovsbr0
            sleep 5
            systemctl restart openvswitch
            sleep 3
            ovs-vsctl add-br {br_name}
            ovs-vsctl add-port {br_name} {bond_name}
            """
            run(cmd)

        with enter_phase("config guest and start it"):
            add_bridge_interface_to_xml(br_name, '52:54:00:11:8f:ea', "16")
            start_guest(guest_xml)
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ["SERVER_GUEST_IP"])

        with enter_phase("ping vm check the connection is ok"):
            send_command("sync_set CLIENT OVS_LINUX_BOND_SERVER_READY")
            gname = xml_tool.xml_get_name(guest_xml)
            connection_ping_check(gname,"ping {} -c 100".format(os.environ["CLIENT_GUEST_IP"]))
            send_command("sync_set CLIENT OVS_LINUX_BOND_SERVER_PING_FIN")

        with enter_phase("ovs linux bond failover test"):
            gname = xml_tool.xml_get_name(guest_xml)
            ovs_linux_bond_failover_test(gname,os.environ["CLIENT_GUEST_IP"])
            send_command("sync_set CLIENT OVS_LINUX_BOND_FAILOVER_TIMEOUT_TEST_END")
            pass

    elif i_am_client():
        with enter_phase("create vf and get vf name"):
            client_nic1_mac = os.environ.get("CLIENT_NIC1_MAC")
            client_nic2_mac = os.environ.get("CLIENT_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(client_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(client_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            slaves = [vf1_name, vf2_name]
        
        with enter_phase("create linux bonding and add it to ovs "):
            br_name = "ovsbr0"
            bond_name = "bond0"
            bond_parameter = ""
            if bond_mode == "active-backup":
                bond_parameter = "miimon=100 mode=1"
            elif bond_mode == "balance-tcp":
                bond_parameter = "miimon=100 mode=4 lacp_rate=1"
            else:
                send_command("rlFail invalid bond mode")

            cmd = f"""
            modprobe bonding {bond_parameter}
            ip link add name {bond_name} type bond
            ip link set dev {bond_name} up
            ip link set {vf1_name} up
            ip link set {vf2_name} up
            ifenslave {bond_name} {vf1_name}
            ifenslave {bond_name} {vf2_name}
            modprobe openvswitch
            systemctl stop openvswitch
            sleep 3
            systemctl start openvswitch
            sleep 3
            ovs-vsctl --if-exists del-br ovsbr0
            sleep 5
            systemctl restart openvswitch
            sleep 3
            ovs-vsctl add-br {br_name}
            ovs-vsctl add-port {br_name} {bond_name}
            """
            run(cmd)

        with enter_phase("config guest and start it"):
            add_bridge_interface_to_xml("ovsbr0", '52:54:00:11:8f:eb', "16")
            start_guest(guest_xml)
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ["CLIENT_GUEST_IP"])

        with enter_phase("wait server ping check finished"):
            send_command("sync_wait SERVER OVS_LINUX_BOND_SERVER_READY")
            send_command("sync_wait SERVER OVS_LINUX_BOND_SERVER_PING_FIN")

        with enter_phase("ovs linux bond failover test"):
            send_command("sync_wait SERVER OVS_LINUX_BOND_FAILOVER_TIMEOUT_TEST_END")
            pass
    else:
        log("Here wrong rule")

    pass

@set_check(0)
def ovs_linux_bond_failover_test(guest_name,remote_ip):
    packet_num = 120000
    file_name = "latencylog"
    cmd = f"""
    rm -f {file_name}
    timeout -s SIGINT 160 ping -n -i 0.001 {remote_ip} -c {packet_num}  > {file_name} &
    """
    log(cmd)
    connection_ping_check(guest_name,cmd)
    with pushd(case_path):
        local.path(case_path + "/latency.log").write(result)
    #here we need down one vf port
    if i_am_server():
        server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
        server_nic2_mac = os.environ.get("SERVER_NIC2_MAC")
        nic1_name = my_tool.get_nic_name_from_mac(server_nic1_mac)
        nic2_name = my_tool.get_nic_name_from_mac(server_nic2_mac)
        vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
        vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
        run(f"ip link set {vf1_name} down && sleep 3 && ip link set {vf1_name} up")
        run(f"ip link set {vf2_name} down && sleep 3 && ip link set {vf2_name} up")
        import time
        time.sleep(180)
        tty_console = bash(f"virsh ttyconsole {guest_name}").value()
        cmd = f""" cat {file_name}"""
        result = my_tool.run_cmd_get_output(tty_console, cmd)
        #log(result)
        #print(result)
        #Now Check packet loss
        cmd = f"""grep received {file_name}"""
        result = my_tool.run_cmd_get_output(tty_console, cmd)
        #result link this
        #10 packets transmitted, 10 received, 0% packet loss, time 24ms
        received_packet = int(str(result).split(',')[1].split()[0])
        lose_packet = int(packet_num) - received_packet
        cmd = f"""grep max {file_name}"""
        result = my_tool.run_cmd_get_output(tty_console,cmd)
        #rtt min/avg/max/mdev = 3.912/4.149/4.295/0.118 ms
        if len(str(result)) > 0:
            max_delay_time = float(str(result).split("=")[1].split('/')[2])
        else:
            max_delay_time = 0
        all_lose_time = max_delay_time + lose_packet
        send_command(f"rlLog 'TEST FAILOVER TIME IS '{all_lose_time}")
        
    else:
        #send_command("sync_wait SERVER BOND_FAILOVER_TIMEOUT_TEST_END")
        pass
    
    pass


@set_check(0)
def ovs_bond_functional_test(bond_mode):
    """
    Current this test only test lacp and active-backup mode
    """
    guest_xml = "g1.xml"
    clear_env()
    with pushd(case_path):
        send_command(f"test -f {guest_xml} && rm -f {guest_xml}")
        send_command(f"test -f {guest_xml} || cp guest.xml {guest_xml}")

    nic1_name = None
    nic2_name = None
    if i_am_server():
        with enter_phase("create vf for each nic"):
            init_physical_topo_with_switch()
            server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
            server_nic2_mac = os.environ.get("SERVER_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(server_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(server_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            slaves = " ".join([vf1_name, vf2_name])
            log_info = f"""
            nic1 name is {nic1_name}
            nic2_name is {nic2_name}
            vf1  name is {vf1_name}
            vf2  name is {vf2_name}
            slaves is {slaves}
            """
            log(log_info)

        with enter_phase("create ovs bond with mode {}".format(bond_mode)):
            bridge_name = "ovsbr0"
            bond_name = "bond0"
            bond_mode = "active-backup"
            bond_extra_parameter = ""
            if bond_mode == "balance-tcp":
                bond_extra_parameter="lacp=active"

            cmd = f"""
            modprobe openvswitch
            systemctl restart openvswitch && sleep 3
            ovs-vsctl --if-exists del-br {bridge_name}
            systemctl restart openvswitch && sleep 3
            ovs-vsctl add-br {bridge_name}
            ovs-vsctl add-bond {bridge_name} {bond_name} {slaves} bond_mode={bond_mode} {bond_extra_parameter}
            # ovs-appctl lacp/show <bond name>
            ovs-vsctl show 
            """
            run(cmd)

        with enter_phase("update guest xml config file and start guest"):
            add_bridge_interface_to_xml("ovsbr0", '52:54:00:11:8f:ea', "16")
            start_guest(guest_xml)
        with enter_phase("configure guest ip and start ping check"):
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ["SERVER_GUEST_IP"])
            send_command("sync_set CLIENT OVS_LINUX_BOND_SERVER_READY")
            gname = xml_tool.xml_get_name(guest_xml)
            connection_ping_check(gname,"ping {} -c 100".format(os.environ["CLIENT_GUEST_IP"]))
            send_command("sync_set CLIENT OVS_LINUX_BOND_SERVER_PING_FIN")
        with enter_phase(f"{bond_mode} failover test "):
            gname = xml_tool.xml_get_name(guest_xml)
            ovs_bond_failover_test(gname,os.environ.get("CLIENT_GUEST_IP"))
            send_command("sync_set CLIENT OVS_BOND_FAILOVER_TIMEOUT_TEST_END")
        with enter_phase("finish ovs bond {} test".format(bond_mode)):
            pass

    elif i_am_client():
        with enter_phase("client side create vf for each nic"):
            client_nic1_mac = os.environ.get("CLIENT_NIC1_MAC")
            client_nic2_mac = os.environ.get("CLIENT_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(client_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(client_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            slaves = " ".join([vf1_name, vf2_name])
            log_info = f"""
            nic1 name is {nic1_name}
            nic2_name is {nic2_name}
            vf1  name is {vf1_name}
            vf2  name is {vf2_name}
            slaves is {slaves}
            """
            log(log_info)
        with enter_phase("create bond with mode {}".format(bond_mode)):
            bridge_name = "ovsbr0"
            bond_name = "bond0"
            bond_mode = "active-backup"
            bond_extra_parameter = ""
            if bond_mode == "balance-tcp":
                bond_extra_parameter="lacp=active"

            cmd = f"""
            modprobe openvswitch
            systemctl restart openvswitch && sleep 3
            ovs-vsctl --if-exists del-br {bridge_name}
            systemctl restart openvswitch && sleep 3
            ovs-vsctl add-br {bridge_name}
            ovs-vsctl add-bond {bridge_name} {bond_name} {slaves} bond_mode={bond_mode} {bond_extra_parameter}
            # ovs-appctl lacp/show <bond name>
            ovs-vsctl show 
            """
            run(cmd)
        with enter_phase("update guest xml config file and start"):
            add_bridge_interface_to_xml("ovsbr0", '52:54:00:11:8f:eb', "16")
            start_guest(guest_xml)
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ["CLIENT_GUEST_IP"])
        with enter_phase("wait server signal to finish ping check test"):
            run("sync_wait SERVER OVS_LINUX_BOND_SERVER_READY")
            run("sync_wait SERVER OVS_LINUX_BOND_SERVER_PING_FIN")
        with enter_phase("enter failover test wait server side signal"):
            send_command("sync_wait SERVER OVS_BOND_FAILOVER_TIMEOUT_TEST_END")
        with enter_phase("finish ovs bond {} test".format(bond_mode)):
            pass

    else:
        log("Here wrong rule")

    pass

@set_check(0)
def ovs_bond_failover_test(guest_name,remote_ip):
    ovs_linux_bond_failover_test(guest_name,remote_ip)
    pass


@set_check(0)
def ovs_dpdk_bond_functional_test(bond_mode):
    clear_env()
    name = sys._getframe().f_code.co_name
    guest_xml = "g1.xml"
    with pushd(case_path):
        send_command(f"test -f {guest_xml} && rm -f {guest_xml}")
        send_command(f"test -f {guest_xml} || cp guest.xml {guest_xml}")

    if i_am_server():
        with enter_phase("init $func_name physical topo"):
            init_physical_topo_with_switch()
            send_command("sleep 5")
            send_command("sync_set client SERVER_START")

        with enter_phase(f"{name} {bond_mode} enable_dpdk"):
            server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
            server_nic2_mac = os.environ.get("SERVER_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(server_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(server_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            vf1_mac  = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac  = pysriov.sriov_get_mac_from_name(vf2_name)
            enable_dpdk(vf1_mac,vf2_mac)

        with enter_phase(f"{name} {bond_mode} create ovs dpdk bonding"):
            bonding_nic(vf1_mac,vf2_mac,bond_mode,1500)
            run("ovs-vsctl set port dpdkbond lacp=passive")
            send_command("sync_wait client LACP_SET_OK")
            send_command("sleep 60")
        
        with enter_phase(f"{name} {bond_mode} show bonding"):
            send_command("ovs-appctl bond/show")
    
        with enter_phase(f"{name} {bond_mode} config and start vm and config ip "):
            numa_node = os.environ.get("SERVER_NUMA")
            vcpu_num = 3
            vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)[1:vcpu_num]
            for i in range(vcpu_num):
                xml_tool.update_vcpu(guest_xml,i,vcpus[0])
            start_guest(guest_xml)
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ.get("SERVER_GUEST_IP"))
        with enter_phase("ovs dpdk bond ping check"):
            cmd = """ ping {} -c 100 """.format(os.environ.get("CLIENT_GUEST_IP"))
            gname = xml_tool.xml_get_name(guest_xml)
            connection_ping_check(gname,cmd)
            send_command("sync_set CLIENT OVS_DPDK_BOND_PING_CHECK_FIN")

                
    elif i_am_client():
        with enter_phase(f"{name} {bond_mode} client side begin"):
            send_command("sync_wait server SERVER_START ")

        with enter_phase(f"{name} {bond_mode} enable dpdk"):
            client_nic1_mac = os.environ.get("CLIENT_NIC1_MAC")
            client_nic2_mac = os.environ.get("CLIENT_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(client_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(client_nic2_mac)
            vf_create(nic1_name, 1)
            vf_create(nic2_name, 1)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            vf1_mac  = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac  = pysriov.sriov_get_mac_from_name(vf2_name)
            enable_dpdk(vf1_mac,vf2_mac)
            send_command("dpdk-devbond -s ")

        with enter_phase(f"{name} {bond_mode} bonding nic"):
            bonding_nic(vf1_mac,vf2_mac,bond_mode,1500)
            send_command("ovs-vsctl set port dpdkbond lacp=active")
            send_command("sync_set server LACP_SET_OK")
            send_command("sleep 70")
            send_command("ovs-appctl bond/show")
        
        with enter_phase(f"{name} {bond_mode} client side config vm xml and start vm "):
            numa_node = os.environ.get("CLIENT_NUMA")
            vcpu_num = 3
            vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)[1:vcpu_num]
            for i in range(vcpu_num):
                xml_tool.update_vcpu(guest_xml,i,vcpus[0])
            start_guest(guest_xml)
            g_name = xml_tool.xml_get_name(case_path + "/" + guest_xml)
            configure_guest(g_name,os.environ.get("CLIENT_GUEST_IP"))
            send_command("sync_wait server SERVER_IPERF_READY")
        with enter_phase("ovs dpdk bond ping check"):
            send_command("sync_wait SERVER OVS_DPDK_BOND_PING_CHECK_FIN")
            pass
    else:
        log("not client or server, test fail")
    pass


@set_check(0)
def ovs_dpdk_and_sriov_dpdk_performance_test(bond_mode):
    clear_env()
    g1xml = "g1.xml"
    g2xml = "g2.xml"
    name = sys._getframe().f_code.co_name
    with pushd(case_path):
        send_command(f"rm -f {g1xml}")
        send_command(f"rm -f {g2xml}")
        send_command(f"test -f {g1xml} || cp guest.xml {g1xml}")
        send_command(f"test -f {g2xml} || cp guest.xml {g2xml}")

    if i_am_server():
        with enter_phase("init $func_name physical topo"):
            init_physical_topo_with_switch()
            send_command("sleep 5")
            send_command("sync_set client SERVER_START")

        with enter_phase("create vf and update qos and enable dpdk "):
            server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
            server_nic2_mac = os.environ.get("SERVER_NIC2_MAC")
            nic1_name = my_tool.get_nic_name_from_mac(server_nic1_mac)
            nic2_name = my_tool.get_nic_name_from_mac(server_nic2_mac)
            vf_create(nic1_name, 2)
            vf_create(nic2_name, 2)
            vf1_name = pysriov.sriov_get_vf_name_from_pf(nic1_name)
            vf2_name = pysriov.sriov_get_vf_name_from_pf(nic1_name,1)
            vf3_name = pysriov.sriov_get_vf_name_from_pf(nic2_name)
            vf4_name = pysriov.sriov_get_vf_name_from_pf(nic2_name,1)
            vf1_mac  = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac  = pysriov.sriov_get_mac_from_name(vf2_name)
            vf3_mac  = pysriov.sriov_get_mac_from_name(vf3_name)
            vf4_mac  = pysriov.sriov_get_mac_from_name(vf4_name)
            # update qos bandwidth vf1 and vf3 10000 and vf2 vf4 3000
            # vf1 and vf3 with passthrough and bonding in testpmd
            # vf2 and vf4 with ovs dpdk bonding
            cmd = f"""
            ip link set {nic1_name} vf 0 max_tx_rate 10000 min_tx_rate 10000
            ip link set {nic2_name} vf 0 max_tx_rate 3000 min_tx_rate 3000
            ip link set {nic1_name} vf 1 max_tx_rate 10000 min_tx_rate 10000
            ip link set {nic2_name} vf 1 max_tx_rate 3000 min_tx_rate 3000
            """
            run(cmd)
            enable_dpdk(vf2_mac,vf4_mac)
            pass

        with enter_phase(f"{name} {bond_mode} create ovs dpdk bonding"):
            bonding_nic(vf2_mac,vf4_mac,bond_mode,1500)
            run("ovs-vsctl set port dpdkbond lacp=passive")
            send_command("sync_wait client LACP_SET_OK")
            send_command("sleep 60")
            send_command("ovs-appctl bond/show")

        with enter_phase(f"{name} {bond_mode} config and start vm and attach vf to vm and config ip "):
            #for g1.xml
            def update_g1():
                numa_node = os.environ.get("SERVER_NUMA")
                vcpu_num = 3
                vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)[1:vcpu_num]
                for i in range(vcpu_num):
                    xml_tool.update_vcpu(g1xml,i,vcpus[0])
                start_guest()
                send_command("sleep 60")
            def update_g2():
                numa_node = os.environ.get("SERVER_NUMA")
                vcpu_num = 3
                vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)[4:vcpu_num]
                for i in range(vcpu_num):
                    xml_tool.update_vcpu(g1xml,i,vcpus[0])
                start_guest()
                send_command("sleep 60")
            update_g1()
            update_g2()
            g2name = xml_tool.xml_get_name(g2xml)
            pysriov.attach_vf_to_vm(vf1_name,g2name)
            pysriov.attach_vf_to_vm(vf3_name,g2name)
        with enter_phase("ovs dpdk bond ping check"):
            pass

    elif i_am_client():
        with enter_phase(f"{name} {bond_mode} client side begin"):
            clear_trex_and_free_hugepage()
            install_trex_and_start()
    else:
        log("not client or server, test fail")
    pass

# #Here Begin ALL test for FD nic partition
# # All Test Items Based on SRIOV VF
# # linux bond
# # ovs bond with linux kernel port
# # OVS DPDK BOND

TEMP_FILE = "/tmp/FD_NIC_PARTITION_FOR_BOND"
if __name__ == "__main__":
    send_command("rlJournalStart")
    main()
    if not os.path.exists(TEMP_FILE):
        with enter_phase("Install package and init environment"):
            update_beaker_tasks_repo()
            add_epel_repo()
            add_yum_profiles()
            install_init_package()
            install_package()
            install_ovs()
            install_driverctl()
            install_dpdk()
        with enter_phase("Update temp file and reboot system"):
            config_hugepage()
            local.path(TEMP_FILE).touch()
            run("rhts-reboot")
    else:       
        init_test_env()
        with enter_phase("ovs linux bond functional test with mode active-backup"):
            ovs_linux_bond_functional_test("active-backup")

        with enter_phase("ovs linux bond functional test with mode balance-tcp"):
            ovs_linux_bond_functional_test("balance-tcp")

        with enter_phase("ovs bond functional test with mode  active-backup"):
            ovs_bond_functional_test("active-backup")

        with enter_phase("ovs bond functional test with mode  balance-tcp"):
            ovs_bond_functional_test("balance-tcp")

        with enter_phase("ovs dpdk bond function test with mode active-backup"):
            ovs_dpdk_bond_functional_test("active-backup")

        with enter_phase("ovs dpdk bond function test with mode balance-tcp"):
            ovs_dpdk_bond_functional_test("balance-tcp")
        
        with enter_phase("QUIT TEST CASE"):
            send_command("fd-nic-partition-quit")

    send_command("rlJournalPrintText")
    send_command("rlJournalEnd")
    time.sleep(30)
    send_command("fd-nic-partition-quit")