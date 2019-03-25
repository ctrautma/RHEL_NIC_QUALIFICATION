#!/usr/bin/env bash

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Run VSPerf tests
#   Author: Christian Trautman <ctrautma@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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

# Detect OS name and version from systemd based os-release file
. /etc/os-release

SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`

if (( $SYSTEM_VERSION_ID < 80 ))
then
    yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
fi

#yum -y install beakerlib
#source /usr/share/beakerlib/beakerlib.sh
yum -y install lrzip
yum -y install tcpdump
yum -y install ethtool


if [ $VERSION_ID == "7.5" ]
then
    dpdk_ver="1711-9"
    one_queue_image="RHEL7-5VNF-1Q.qcow2"
    two_queue_image="RHEL7-5VNF-2Q.qcow2"
    one_queue_zip="RHEL7-5VNF-1Q.qcow2.lrz"
    two_queue_zip="RHEL7-5VNF-2Q.qcow2.lrz"
elif [ $VERSION_ID == "7.6" ]
then
    dpdk_ver="1711-9"
    one_queue_image="RHEL76-1Q.qcow2"
    two_queue_image="RHEL76-2Q.qcow2"
    one_queue_zip="RHEL76-1Q.qcow2.lrz"
    two_queue_zip="RHEL76-2Q.qcow2.lrz"
fi

fail() 
{
    # Param 1, Fail Header
    # Param 2, Fail Message
    echo ""
    echo "!!! $1 FAILED !!!"
    echo "!!! $2 !!!"
    echo ""
    exit 1
}


OS_checks() 
{
    echo "*** Running System Checks ***"
    sleep 1

    # Verify user is root
    echo "*** Running User Check ***"
    sleep 1

    if [ $USER != "root" ]
    then
        fail "User Check" "Must be logged in as root"
    fi

    # Verify OS is Rhel
    echo "*** Running OS Check ***"
    sleep 1

    if [ $ID != "rhel" ]
    then
        fail "OS Check" "OS Much be RHEL"
    fi

    # Install lrzip
    echo "*** Installing lrzip if needed ***"
    if ! [ `command -v lrzip ` ]
    then
        rpm -ivh lrzip-0.616-5.el7.x86_64.rpm || fail "lrzip install" "Failed to install lrzip"
    fi
}

log_folder_check() 
{
    # create log folder
    echo "*** Creating log folder ***"
    if ! [ -d /root/RHEL_NIC_QUAL_LOGS ]
    then
        mkdir /root/RHEL_NIC_QUAL_LOGS || fail "log folder creation" "Cannot create log folder in root home folder"
    fi
    time_stamp=$(date +%Y-%m-%d-%T)
    NIC_LOG_FOLDER="/root/RHEL_NIC_QUAL_LOGS/$time_stamp"
    mkdir $NIC_LOG_FOLDER || fail "log folder creation" "Cannot create time stamp folder for logs in root home folder"
    echo "NIC_LOG_FOLDER=$NIC_LOG_FOLDER" > /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
    echo "*** Placing all output logs to $NIC_LOG_FOLDER"
    return 0
}

conf_checks() 
{
    # get the cat proc cmdline for parsing the next few checks
    PROCESS_CMD_LINE=`cat /proc/cmdline`

    # Verify iommu is enabled for vfio-pci
    echo "*** Checking for iommu enablement ***"
    sleep 1

    if ! [[ `echo $PROCESS_CMD_LINE | grep "intel_iommu=on"` ]]
    then
        fail "Iommu Enablement" "Please enable IOMMU mode in your grub config"
    fi

    echo "*** Checking Tunings ***"
    sleep 1

    if ! [[ `tuned-adm active | grep cpu-partitioning` ]]
    then
        fail "Tuned-adm" "cpu-partitioning profile must be active"
    fi

    if ! [[ `echo $PROCESS_CMD_LINE | grep "nohz_full=[0-9]"` ]]
    then
        fail "Tuned Config" "Must set cores to isolate in tuned-adm profile"
    fi
    return 0
}

hugepage_checks() 
{
    echo "*** Checking Hugepage Config ***"
    sleep 1

    if ! [[ `cat /proc/meminfo | awk /Hugepagesize/ | awk /1048576/` ]]
    then
        fail "Hugepage Check" "Please enable 1G Hugepages"
    fi
    return 0
}

config_file_checks() 
{

    echo "*** Checking Config File ***"
    sleep 1

    if test -f ./Perf-Verify.conf
    then
        set -o allexport
        source Perf-Verify.conf
        set +o allexport
        if [[ -z $NIC1 ]] || [[ -z $NIC2 ]]
        then
            fail "NIC Param" "NIC Params not set in Perf-Verify.conf file"
        fi
        if [ -z $PMD2MASK ] || [ -z $PMD4MASK ]
        then
            fail "PMD Mask PARAM" "PMD2MASK Param and/or PMD4MASK not set in Perf-Verify.conf file"
        fi
        if [ -z $VCPU1 ] || [ -z $VCPU2 ] || [ -z $VCPU3 ] || [ -z $VCPU4 ] || [ -z $VCPU5 ]
        then
            fail "VCPU Params" "Guest VCPU Param not set in Perf-Verify.conf file"
        fi
        if [ -z $TRAFFICGEN_TREX_HOST_IP_ADDR ] || [ -z $TRAFFICGEN_TREX_USER ] || [ -z $TRAFFICGEN_TREX_BASE_DIR ] || [ -z $TRAFFICGEN_TREX_PORT1 ] || [ -z $TRAFFICGEN_TREX_PORT2 ]
        then
            fail "TREX Params" "T-Rex settings not set in Perf-Verify.conf file"
        fi
    else
        fail "Config File" "Cannot locate Perf-Verify.conf"
    fi
    return 0
}

nic_card_check() 
{
    echo "*** Checking for NIC cards ***"
    if [[ ! `ip a | grep $NIC1` ]] ||  [[ ! `ip a | grep $NIC2` ]]
    then
        fail "NIC Check" "NIC $NIC1 or NIC $NIC2 cannot be seen by kernel"
    fi
    return 0
}

rpm_check() 
{
    echo "*** Checking for installed RPMS ***"
    sleep 1

    if ! [[ `rpm -qa | grep ^openvswitch-[0-9]` ]]
    then
        fail "Openvswitch rpm" "Please install Openvswitch rpm"
    fi
    if ! [ `rpm -qa | grep dpdk-tools` ]
    then
        fail "DPDK Tools rpm" "Please install dpdk tools rpm"
    fi
    if ! [ `rpm -qa | grep dpdk-[0-9]` ]
    then
        fail "DPDK package rpm" "Please install dpdk package rpm"
    fi
    if ! [ `rpm -qa | grep qemu-kvm-rhev` ]
    then
        fail "QEMU-KVM-RHEV rpms" "Please install qemu-kvm-rhev rpm"
    fi

    if (( $SYSTEM_VERSION_ID < 80 ))
	then
        if ! [ `rpm -qa | grep qemu-img-rhev` ]
        then
            fail "QEMU-IMG-RHEV rpms" "Please install qemu-img-rhev rpm"
        fi
        if ! [ `rpm -qa | grep qemu-kvm-tools-rhev` ]
        then
            fail "QEMU-KVM-TOOLS-RHEV rpms" "Please install qemu-kvm-tools-rhev rpm"
        fi
	else
        if ! [ `rpm -qa | grep qemu-img` ]
        then
            fail "QEMU-IMG rpms" "Please install qemu-img rpm"
        fi
        if ! [ `rpm -qa | grep qemu-kvm` ]
        then
            fail "QEMU-KVM rpms" "Please install qemu-kvm rpm"
        fi
	fi

    return 0
}

network_connection_check() 
{
    echo "*** Checking connection to people.redhat.com ***"
    if ping -c 1 people.redhat.com &> /dev/null
    then
        echo "*** Connection to server succesful ***"
    else
        fail "People.redhat.com connection fail" "!!! Cannot connect to people.redhat.com, please verify internet connection !!!"
    fi
    return 0
}

ovs_running_check() 
{
    echo "*** Checking for running instance of Openvswitch ***"
    if [ `pgrep ovs-vswitchd` ] || [ `pgrep ovsdb-server` ]
    then
        fail "Openvswitch running" "It appears Openvswitch may be running, please stop all services and processes"
    fi
}

download_VNF_image() 
{
    if [ ! -f $one_queue_image ] || [ ! -f $two_queue_image ]
    then
        echo ""
        echo "***********************************************************************"
        echo "*** Downloading and decompressing VNF image. This may take a while! ***"
        echo "***********************************************************************"
        echo ""
        wget people.redhat.com/ctrautma/$one_queue_zip || fail "VNF download" "Unabled to download VNF"
        wget people.redhat.com/ctrautma/$two_queue_zip || fail "VNF download" "Unable to download VNF 2Q"
        lrzip -d $one_queue_zip || fail "VNF decompress" "Unable to decompress VNF zip"
        lrzip -d $two_queue_zip || fail "VNF decompress" "Unable to decompress VNF zip"
        rm -f $one_queue_zip
        rm -f $two_queue_zip
    fi

}


install_rpms()
{
    #add repo
	if (( $SYSTEM_VERSION_ID < 80 ))
	then
		/bin/bash ./repo.sh
        yum -y install python-netifaces
        rpm -qa | grep python36  || yum -y install python36 python36-devel scl-utils
	else
        yum -y install python3-netifaces
	fi

    yum -y install python3-pyelftools
	rpm -qa | grep yum-utils || yum -y install yum-utils
	rpm -qa | grep wget || yum install -y wget nano ftp yum-utils git tuna openssl sysstat
	rpm -qa | grep tuned-profiles-cpu-partitioning || yum -y install tuned-profiles-cpu-partitioning
	
    #install libvirt
	yum install -y libvirt libvirt-devel virt-install virt-manager virt-viewer

	systemctl restart libvirtd
	
    #install python
	yum install -y python
	
    #install zmq for trex 
	yum install -y czmq-devel
	
    #here for virt-copy-in
	yum install -y libguestfs-tools
    
    #add ethtools
    yum -y install ethtool

    #for vim
    yum -y install vim
}

#get nic name from mac address
get_nic_name_from_mac()
{
    local mac_addr=$1
    local temp_addr
    for i in `ls /sys/class/net/`
    do
        temp_addr=`ethtool -P $i | awk '{print $NF}'`
        if [[ $mac_addr == $temp_addr ]]
        then
            echo $i
            return 0
        fi
    done
    echo "name-error"
    return 1
}

init_python_env()
{
	if (( $SYSTEM_VERSION_ID >= 80 ))
	then
		python3 -m venv ${CASE_PATH}/venv
	else
		python36 -m venv ${CASE_PATH}/venv
	fi

    source venv/bin/activate
    yum install -y libnl3-devel

    pip install --upgrade pip
    pip install fire
    pip install psutil
    pip install paramiko
    pip install xmlrunner
	pip install netifaces
    pip install pyelftools
	pip install libvirt-python
	pip install argparse
	pip install plumbum
	pip install ethtool
	pip install shell
}


enable_dpdk() 
{
    local nic1_mac=$1
    local nic2_mac=$2
    local nic1_name=`get_nic_name_from_mac $nic1_mac`
    local nic2_name=`get_nic_name_from_mac $nic2_mac`
    local nic1_businfo=$(ethtool -i $nic1_name | grep "bus-info" | awk  '{print $2}')
    local nic2_businfo=$(ethtool -i $nic2_name | grep "bus-info" | awk  '{print $2}')
    modprobe -r vfio-pci
    modprobe -r vfio
    modprobe vfio-pci
    modprobe vfio
    local driver_name=`ethtool -i $nic1_name | grep driver | awk '{print $NF}'`
    if [ "$driver_name" == "mlx5_core" ];then
        rlLog "************************************************"
        rlLog "This Driver is Mallenox , So just return 0"
        rlLog "************************************************"
        return 0
    fi

    if [[ -f /usr/share/dpdk/usertools/dpdk-devbind.py ]]; then
        echo "using dpdk-devbind.py set the vfio-pci driver to nic"
        /usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci ${nic1_businfo}
        /usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci ${nic2_businfo}
        /usr/share/dpdk/usertools/dpdk-devbind.py --status
    else
        echo "using driverctl set the vfio-pci driver to nic"
        driverctl -v set-override $nic1_businfo vfio-pci
        sleep 3
        driverctl -v set-override $nic2_businfo vfio-pci
        sleep 3
        driverctl -v list-devices|grep vfio-pci
    fi
}

bonding_nic() 
{
    local nic1_mac=$1
    local nic2_mac=$2
    local bond_mode=$3
    local mtu_val=$4
    
    # if [[ "$NIC_DRIVER" == "nfp" ]];then
    #     #here need update /etc/sysconfig/openvswitch
    #     sed -ie 's/OVS_USER_ID/#OVS_USER_ID/g' /etc/sysconfig/openvswitch 

    # fi
    enable_openvswitch_as_root_user

    local pmd_cpu_mask
    if i_am_server;then
        pmd_cpu_mask=$SERVER_PMD_CPU_MASK
    elif i_am_client;then
        pmd_cpu_mask=$CLIENT_PMD_CPU_MASK
    fi

    

	modprobe openvswitch
	systemctl stop openvswitch
	sleep 3
	systemctl start openvswitch
	sleep 3

	ovs-vsctl --if-exists del-br ovsbr0
	sleep 5

	ovs-vsctl set Open_vSwitch . other_config={}
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
	ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="4096,4096"
	ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask="$pmd_cpu_mask"
    ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
	systemctl restart openvswitch
	sleep 3
	ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev

    ovs-vsctl add-bond ovsbr0 dpdkbond dpdk0 dpdk1 "bond_mode=${bond_mode}" \
    -- set Interface dpdk0 type=dpdk options:dpdk-devargs=class=eth,mac=${nic1_mac} mtu_request=${mtu_val} \
    -- set Interface dpdk1 type=dpdk options:dpdk-devargs=class=eth,mac=${nic2_mac} mtu_request=${mtu_val}

    #set dpdkbond port with vlan mode trunk and permit all vlans
    ovs-vsctl set Port dpdkbond vlan_mode=trunk
    ovs-vsctl list Port dpdkbond

    #set updelay and downdelay for test
    ovs-vsctl set Port dpdkbond bond_updelay=5
    ovs-vsctl set Port dpdkbond bond_downdelay=5

    local updelay=`ovs-vsctl list Port dpdkbond | grep bond_updelay | awk '{print $NF}'`
    local downdelay=`ovs-vsctl list Port dpdkbond | grep bond_downdelay | awk '{print $NF}'`
    rlAssertEquals "Check bond up delay time " "$updelay" "5"
    rlAssertEquals "Check bond down delay time " "$downdelay" "5"
    ovs-vsctl list Port dpdkbond
	
    #ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuser
    ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost0
	#chmod 777 /var/run/openvswitch/vhost0

	ovs-ofctl del-flows ovsbr0
	ovs-ofctl add-flow ovsbr0 actions=NORMAL

	sleep 2
	ovs-vsctl show
	sleep 5
	echo "after bonding nic, check the bond status"
	ovs-appctl bond/show
    sleep 30
    ovs-appctl bond/show
}


vcpupin_in_xml()
{
    local numa_node=$1
    local number_of_required_cpu_cores=$2
    local template_xml=$3
    local new_xml=$4

    local cpu_list=($(cpu_list_on_numa $numa_node))

    pushd $CASE_PATH 1>/dev/null
    cp $template_xml $new_xml

    python tools.py update_vcpu $new_xml 0  ${cpu_list[0]}

    for ((i=1; i<=$number_of_required_cpu_cores; i++))
    do
            if (( ${i}%2 ))
            then
                python tools.py update_vcpu $new_xml $i  ${cpu_list[$(($i/2+1))]}
            else
                local_temp_cpu=$(cat /sys/devices/system/cpu/cpu${cpu_list[$(($i/2))]}/topology/thread_siblings_list | awk -F ',' '{print $NF}')
                python tools.py update_vcpu $new_xml $i $local_temp_cpu
            fi
    done
    python tools.py update_numa $new_xml $numa_node
    if [ $5 == 'client' ]
    then
        python tools.py update_vhostuser_interface $new_xml "52:54:00:11:8f:ea" "0x00"
    elif [ $5 == 'server' ]
    then
        python tools.py update_vhostuser_interface $new_xml "52:54:00:11:8f:e8" "0x00"
    fi
	popd 1>/dev/null
}


start_guest()
{
    systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd
    
    if [[ $CUSTOMER_PFT == "true" ]]; then
        [[ -f /root/$(basename $IMG_GUEST) ]] || wget -P /root/  $IMG_GUEST > /dev/null 2>&1
        pushd /root 1>/dev/null
        [[ -f /root/rhel7.5-vsperf.qcow2 ]] || lrzip -d "$(basename $IMG_GUEST)"
        [[ -f /root/rhel7.5-vsperf.qcow2 ]] || mv $(basename -s .lrz $IMG_GUEST) rhel7.5-vsperf.qcow2
        popd 1>/dev/null
        virsh define ${CASE_PATH}/g1.xml
        chmod 777 /root/
        virsh start guest30032
    else
        local image_name=`basename ${IMG_GUEST}`
        [[ -f /root/rhel.qcow2 ]] && rm -f /root/rhel.qcow2
        wget -P /root/ ${IMG_GUEST} > /dev/null 2>&1
        pushd /root/
            mv $image_name rhel.qcow2
        popd
        chmod 777 /root/
        local udev_file=60-persistent-net.rules
        touch $udev_file
        cat > $udev_file <<EOF
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:02:00.0", NAME:="eth0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:03:00.0", NAME:="eth1"
EOF

        virt-copy-in -a /root/rhel.qcow2 $udev_file /etc/udev/rules.d/
        #Here add dpdk rpm to guest
        rm -rf /root/${GUEST_DPDK_VERSION}
        mkdir -p /root/${GUEST_DPDK_VERSION}
        wget -P /root/${GUEST_DPDK_VERSION}/ ${GUEST_DPDK_URL}      > /dev/null 2>&1
        wget -P /root/${GUEST_DPDK_VERSION}/ ${GUEST_DPDK_TOOL_URL} > /dev/null 2>&1
        virt-copy-in -a /root/rhel.qcow2 /root/${GUEST_DPDK_VERSION}/ /root/
        sleep 5
        
        virsh define ${CASE_PATH}/g1.xml
        chmod 777 /root/
        virsh start guest30032
    fi
}

destroy_guest()
{
    virsh destroy guest30032
    virsh undefine guest30032
}

configure_guest()
{
	local cmd=(
            {nmcli dev set eth1 managed no}
            {systemctl stop firewalld}
            {iptables -t filter -P INPUT ACCEPT}
			{iptables -t filter -P FORWARD ACCEPT}
			{iptables -t filter -P OUTPUT ACCEPT}
			{iptables -t mangle -P PREROUTING ACCEPT}
			{iptables -t mangle -P INPUT ACCEPT}
			{iptables -t mangle -P FORWARD ACCEPT}
			{iptables -t mangle -P OUTPUT ACCEPT}
			{iptables -t mangle -P POSTROUTING ACCEPT}
			{iptables -t nat -P PREROUTING ACCEPT}
			{iptables -t nat -P INPUT ACCEPT}
			{iptables -t nat -P OUTPUT ACCEPT}
			{iptables -t nat -P POSTROUTING ACCEPT}
			{iptables -t filter -F}
			{iptables -t filter -X}
			{iptables -t mangle -F}
			{iptables -t mangle -X}
			{iptables -t nat -F}
			{iptables -t nat -X}
			{ip6tables -t filter -P INPUT ACCEPT}
			{ip6tables -t filter -P FORWARD ACCEPT}
			{ip6tables -t filter -P OUTPUT ACCEPT}
			{ip6tables -t mangle -P PREROUTING ACCEPT}
			{ip6tables -t mangle -P INPUT ACCEPT}
			{ip6tables -t mangle -P FORWARD ACCEPT}
			{ip6tables -t mangle -P OUTPUT ACCEPT}
			{ip6tables -t mangle -P POSTROUTING ACCEPT}
			{ip6tables -t nat -P PREROUTING ACCEPT}
			{ip6tables -t nat -P INPUT ACCEPT}
			{ip6tables -t nat -P OUTPUT ACCEPT}
			{ip6tables -t nat -P POSTROUTING ACCEPT}
			{ip6tables -t filter -F}
			{ip6tables -t filter -X}
			{ip6tables -t mangle -F}
			{ip6tables -t mangle -X}
			{ip6tables -t nat -F}
			{ip6tables -t nat -X}
			{ip addr add $1/24 dev eth1}
            {ip -d addr show}
                )

	vmsh cmd_set guest30032 "${cmd[*]}"
}


update_guest_isolate_cpus()
{
    local cmd=(
    {sed -i 's/GRUB_CMDLINE_LINUX=.*/& isolcpus=1,2/g' /etc/default/grub}
    {echo "isolated_cores=1,2" \>\> /etc/tuned/cpu-partitioning-variables.conf}
    {tuned-adm profile cpu-partitioning}
    {echo "options vfio enable_unsafe_noiommu_mode=1" \> /etc/modprobe.d/vfio.conf}
    {grub2-mkconfig -o /boot/grub2/grub.cfg}
    )
    vmsh cmd_set guest30032 "${cmd[*]}"
}

#{modprobe  vfio enable_unsafe_noiommu_mode=1}
guest_start_testpmd()
{
    if (( $SYSTEM_VERSION_ID >= 80 ))
    then
        update_guest_isolate_cpus
        virsh restart guest30032
    fi
    local cmd=(
        {/root/one_gig_hugepages.sh 1}
        {rpm -ivh  /root/$GUEST_DPDK_VERSION/dpdk*.rpm}
        {modprobe -r vfio_iommu_type1}
        {modprobe -r vfio}
        {modprobe  vfio }
        {modprobe vfio-pci}
        {ip link set eth1 down}
        {dpdk-devbind -b vfio-pci 0000:00:09.0}
        {dpdk-devbind -b vfio-pci 0000:03:00.0}
        {dpdk-devbind --status}
            )
    vmsh cmd_set guest30032 "${cmd[*]}"
    local q_num=1
    local guest_dpdk_ver=`echo $GUEST_DPDK_VERSION | awk -F '-' '{print $1}' | tr -d '.'`
    local hw_vlan_flag=""
    local legacy_mem=""
    if (( $guest_dpdk_ver >= 1811))
    then
        legacy_mem=" --legacy-mem "      
        hw_vlan_flag=""
    else
        hw_vlan_flag="--disable-hw-vlan"
    fi
    VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd guest30032 "testpmd -l 0,1,2  --socket-mem 1024 ${legacy_mem} -n 4 -- --forward-mode=macswap --port-topology=chained ${hw_vlan_flag} --disable-rss -i --rxq=${q_num} --txq=${q_num} --rxd=256 --txd=256 --nb-cores=2 --auto-start"
}

update_ssh_trust()
{
        mkdir -p ~/.ssh
        rm -f ~/.ssh/*
        touch ~/.ssh/known_hosts
        chmod 644 ~/.ssh/known_hosts
        ssh-keyscan $TREX_SERVER_IP >> ~/.ssh/known_hosts
        echo 'y\n' | ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
        python tools.py config-ssh-trust ~/.ssh/id_rsa.pub $TREX_SERVER_IP root ${TREX_SERVER_PASSWORD}
}

clear_dpdk_interface()
{
    if rpm -qa | grep dpdk-tools
    then
        local bus_list=`dpdk-devbind -s | grep  -E drv=vfio-pci\|drv=igb | awk '{print $1}'`
        for i in $bus_list
        do
            kernel_driver=`lspci -s $i -v | grep Kernel  | grep modules  | awk '{print $NF}'`
            dpdk-devbind -b $kernel_driver $i
        done
        rlRun "dpdk-devbind -s "
    fi
    return 0
}

clear_env()
{
    systemctl start openvswitch
    ovs-vsctl --if-exists del-br ovsbr0
    virsh destroy guest30032
    virsh undefine guest30032
    systemctl stop openvswitch
    #rhts-reboot
    rlRun clear_trex
    rlRun "clear_dpdk_interface" "0,1"
    rlRun -l "clear_hugepage"
    if i_am_server; then
        local nic1_name=`get_nic_name_from_mac $SERVER_NIC1_MAC`
        local nic2_name=`get_nic_name_from_mac $SERVER_NIC2_MAC`
        ip link set $nic1_name down
        ip link set $nic2_name down
    elif i_am_client; then
        local nic1_name=`get_nic_name_from_mac $CLIENT_NIC1_MAC`
        local nic2_name=`get_nic_name_from_mac $CLIENT_NIC2_MAC`
        ip link set $nic1_name down
        ip link set $nic2_name down
    else
        echo "Here wrong rule"        
    fi

    return 0
}


bonding_test_trex()
{
    pushd $CASE_PATH
    #get trex server ip 
    rm -f /tmp/conn_is_ok
    timeout -s SIGINT 3 ping $TREX_SERVER_IP -c 3 > /tmp/conn_is_ok
    loss_check=`grep packets /tmp/conn_is_ok | awk '{print $6}'`
    if [ "${loss_check::-1}" == "100" ];then
            echo "trex server "$TREX_SERVER_IP" is no up "
    else
            install_rpms
            init_python_env
            update_ssh_trust
    fi
    #first use short time quick find the near value and test it long it to find is there any packet loss.
    local trex_dir=`basename .tar.gz $TREX_URL`
    local trex_name=`basename $TREX_URL`
    [ -d $trex_dir ] || wget $TREX_URL > /dev/null 2>&1
    [ -d $trex_dir ] || tar -xvf $trex_name > /dev/null 2>&1
    rlRun "python ./trex_sport.py -c $TREX_SERVER_IP -t 60 --pkt_size=64 -m 10"

    popd
    return 0
}



run_tests() {
TESTLIST=$1

if [ "$TESTLIST" == "pvp_cont" ]
then
    echo "*** Running 1500 Byte PVP VSPerf verify check ***"

scl enable rh-python34 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf pvp_cont --test-params="TRAFFICGEN_DURATION=30; TRAFFICGEN_PKT_SIZES=1500,"
EOF
fi


if [ "$TESTLIST" == "ALL" ] || [ "$TESTLIST" == "1Q" ]
then
    echo ""
    echo "***********************************************************"
    echo "*** Running 64/1500 Bytes 2PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "***********************************************************"
    echo ""

scl enable rh-python34 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput &>$NIC_LOG_FOLDER/vsperf_pvp_2pmd.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid
fi

if [ "$TESTLIST" == "ALL" ] || [ "$TESTLIST" == "2Q" ]
then
    echo ""
    echo "*******************************************************************"
    echo "*** Running 64/1500 Bytes 2 queue 4PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "*******************************************************************"
    echo ""

scl enable rh-python34 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --conf-file=/root/vswitchperf/twoqueue.conf &>$NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid
fi

if [ "$TESTLIST" == "ALL" ] || [ "$TESTLIST" == "Jumbo" ]
then
    echo ""
    echo "*************************************************************"
    echo "*** Running 2000/9000 Bytes 2PMD PVP OVS/DPDK VSPerf TEST ***"
    echo "*************************************************************"
    echo ""

scl enable rh-python34 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --test-params="TRAFFICGEN_PKT_SIZES=2000,9000; VSWITCH_JUMBO_FRAMES_ENABLED=True" &>$NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid
fi

if [ "$TESTLIST" == "ALL" ] || [ "$TESTLIST" == "Kernel" ]
then
    echo ""
    echo "********************************************************"
    echo "*** Running 64/1500 Bytes PVP OVS Kernel VSPerf TEST ***"
    echo "********************************************************"
    echo ""

scl enable rh-python34 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --vswitch=OvsVanilla --vnf=QemuVirtioNet --test-params="TRAFFICGEN_LOSSRATE=0.002" &>$NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid
fi
}

spinner() {
if [ $# -eq 1 ]
then
    pid=$1
else
    pid=$! # Process Id of the previous running command
fi

spin[0]="-"
spin[1]="\\"
spin[2]="|"
spin[3]="/"

echo -n "${spin[0]}"
while kill -0 $pid 2>/dev/null
do
  for i in "${spin[@]}"
  do
        echo -ne "\b$i"
        sleep 0.1
  done
done

}

vsperf_make() {
    if [ ! -f ~/vsperf_install.log ]
    then
        echo "*** Running VSPerf installation ***"

        # since we are using rpms and due to build issues only run T-Rex build
        sed -i s/'SUBDIRS += l2fwd'/'#SUBDIRS += l2fwd'/ src/Makefile
        sed -i s/'SUBDIRS += dpdk'/'#SUBDIRS += dpdk'/ src/Makefile
        sed -i s/'SUBDIRS += qemu'/'#SUBDIRS += qemu'/ src/Makefile
        sed -i s/'SUBDIRS += ovs'/'#SUBDIRS += ovs'/ src/Makefile
        sed -i s/'SUBDIRS += vpp'/'#SUBDIRS += vpp'/ src/Makefile
        sed -i s/'SUBBUILDS = src_vanilla'/'#SUBBUILDS = src_vanilla'/ src/Makefile
        if ! [ -d "./systems/rhel/$VERSION_ID" ]
        then
            cp -R systems/rhel/7.2 systems/rhel/$VERSION_ID
        fi
        cd systems
        sed -i 's/source\s"$VSPERFENV_DIR".*/&\npip install --upgrade pip/' rhel/$VERSION_ID/prepare_python_env.sh
        sed -i 's/source\s"$VSPERFENV_DIR".*/&\npip install --upgrade setuptools/' rhel/$VERSION_ID/prepare_python_env.sh
        ./build_base_machine.sh &> $NIC_LOG_FOLDER/vsperf_install.log &
        spinner
        cd ..

        if ! [[ `grep "finished making all" $NIC_LOG_FOLDER/vsperf_install.log` ]]
        then
            fail "VSPerf Install" "VSPerf installation failed, please check log at $NIC_LOG_FOLDER/vsperf_install.log"
        fi
    fi
}

print_results() {
if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp*' -print -quit)"
then
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
########################################################
#             RESULTS OF ALL VSPERF TESTS              #
#                                                      #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_2pmd.log' -print -quit)"
then
mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #
# 1500 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_4pmd-2q.log' -print -quit)"
then
mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte 4PMD 2Q OVS/DPDK PVP test result: ${array[0]} #
# 1500 Byte 4PMD 2Q OVS/DPDK PVP test result: ${array[1]} #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_2pmd_jumbo.log' -print -quit)"
then
mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 2000 Byte 2PMD OVS/DPDK Phy2Phy test result: ${array[0]} #
# 9000 Byte 2PMD OVS/DPDK Phy2Phy test result: ${array[1]} #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_ovs_kernel.log' -print -quit)"
then
mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte OVS Kernel PVP test result: ${array[0]} #
# 1500 Byte OVS Kernel PVP test result: ${array[1]} #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp*' -print -quit)"
then
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
########################################################
EOT
cat $NIC_LOG_FOLDER//vsperf_results.txt
fi

}

copy_config_files_to_log_folder() {

cp /root/vswitchperf/conf/* $NIC_LOG_FOLDER
cp /root/RHEL_NIC_QUALIFICATION/Perf-Verify.conf $NIC_LOG_FOLDER

}
function usage () {
   cat <<EOF
Usage: $progname [-t test to execute] [-h print help]
-t tests to execute ['1Q, 2Q, Jumbo, Kernel, pvp_cont'] default is to run all tests
-h print this help message
EOF
   exit 0
}


main() {
# run all checks
OS_checks
log_folder_check
hugepage_checks
conf_checks
config_file_checks
nic_card_check
rpm_check
network_connection_check
ovs_running_check
# finished running checks

TESTLIST="ALL"

progname=$0
while getopts t:l:h FLAG; do
   case $FLAG in

   t)  TESTLIST1=$OPTARG
       echo "Running test(s) $OPTARG"
       ;;
   h)  echo "found $opt" ; usage ;;
   \?)  usage ;;
   esac
done

if [[ ! "$TESTLIST1" == "" ]]
then
    TESTLIST=$TESTLIST1
    
fi

git_clone_vsperf
vsperf_make
customize_VSPerf_code
download_VNF_image
download_conf_files
generate_2queue_conf
run_tests $TESTLIST
print_results
copy_config_files_to_log_folder
}

if [ "${1}" != "--source-only" ]
then
    main "${@}"
fi
