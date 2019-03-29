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
CASE_PATH="$(dirname $(readlink -f $0))"

. /etc/os-release

SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`

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

pytool()
{
    echo "args "$*
    python tools.py $*
}

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

loginfo()
{
    # Param 1 log info 
    echo ""
    echo "####################################"
    echo $1
    echo "####################################"
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
    pushd $CASE_PATH
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
    popd

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
    yum -y install lrzip

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

enalbe_python_venv()
{
    if (( $SYSTEM_VERSION_ID >= 80 ))
	then
		python3 -m venv ${CASE_PATH}/venv
	else
        yum install -y python36
		python36 -m venv ${CASE_PATH}/venv
	fi
    source venv/bin/activate
}

init_python_env()
{
    enalbe_python_venv
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
        loginfo "************************************************"
        loginfo "This Driver is Mallenox , So just return 0"
        loginfo "************************************************"
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
        driverctl -v list-devices | grep vfio-pci
    fi
}

ovs_bridge_with_kernel()
{
    local nic1_mac=$1
    local nic2_mac=$2
    local mtu_val=$3
    local pmd_cpu_mask=$4
    local queue_num=$5

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

    ovs-vsctl add-port ovsbr0 dpdk0 -- set Interface dpdk0 type=dpdk options:dpdk-devargs="class=eth,mac=${nic1_mac}"
    ovs-vsctl add-port ovsbr0 dpdk1 -- set Interface dpdk1 type=dpdk options:dpdk-devargs="class=eth,mac=${nic2_mac}"
	
    ovs-vsctl add-port ovsbr0 vhost0 -- set interface vhost0 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost0
    ovs-vsctl add-port ovsbr0 vhost1 -- set interface vhost1 type=dpdkvhostuserclient options:vhost-server-path=/tmp/vhost1

	ovs-ofctl del-flows ovsbr0
	ovs-ofctl add-flow ovsbr0 actions=NORMAL

	sleep 2
	ovs-vsctl show

}


ovs_bridge_with_dpdk()
{
    local nic1_mac=$1
    local nic2_mac=$2
    local mtu_val=$3
    local pmd_cpu_mask=$4

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

    ovs-vsctl add-port ovsbr0 dpdk0 \
    -- set Interface dpdk0 type=dpdk \
    options:dpdk-devargs="class=eth,mac=${nic1_mac}" mtu_request=$mtu_val
    
    ovs-vsctl add-port ovsbr0 dpdk1 \
    -- set Interface dpdk1 type=dpdk \
    options:dpdk-devargs="class=eth,mac=${nic2_mac}" mtu_request=$mtu_val
	
    ovs-vsctl add-port ovsbr0 vhost0 \
    -- set interface vhost0 \
    type=dpdkvhostuserclient \
    options:vhost-server-path=/tmp/vhost0
    
    ovs-vsctl add-port ovsbr0 vhost1 \
    -- set interface vhost1 \
    type=dpdkvhostuserclient \
    options:vhost-server-path=/tmp/vhost1

	ovs-ofctl del-flows ovsbr0
	ovs-ofctl add-flow ovsbr0 actions=NORMAL

	sleep 2
	ovs-vsctl show
}

vcpupin_in_xml()
{
    local numa_node=$1
    local template_xml=$2
    local new_xml=$3
    local cpu_list=$4
    pushd $CASE_PATH 1>/dev/null

    config_file_checks
    
    cp $template_xml $new_xml
    
    pytool xml_add_vcpupin_item $new_xml ${#cpu_list[@]}

    for i in `seq ${#cpu_list[@]}`
    do
        local index=$((i-1))
        pytool update_vcpu $new_xml $index ${cpu_list[$index]}
    done

    pytool update_numa $new_xml $numa_node
	popd 1>/dev/null

}

start_guest()
{
    local guest_xml=$1

    pushd $CASE_PATH

    systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd

    download_VNF_image

    #update guest xml config for image
    #pytool update_image_source $guest_xml $image_name
        
    virsh define ${CASE_PATH}/${guest_xml}

    virsh start gg    

    popd
}

destroy_guest()
{
    virsh destroy gg
    virsh undefine gg
}

configure_guest()
{
    local cmd=$(
		cat <<EOF
        stty rows 24 cols 120 
		nmcli dev set eth1 managed no
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
EOF
	)

	pytool login_vm_and_run_cmds gg "${cmd[*]}"
}


#{modprobe  vfio enable_unsafe_noiommu_mode=1}
guest_start_testpmd()
{
    local cmd=$(
        cat << EOF
        /root/one_gig_hugepages.sh 1
        rpm -ivh  /root/$GUEST_DPDK_VERSION/dpdk*.rpm
        modprobe -r vfio_iommu_type1
        modprobe -r vfio
        modprobe  vfio 
        modprobe vfio-pci
        #ip link set eth1 down
        #dpdk-devbind -b vfio-pci 0000:03:00.0
        dpdk-devbind --status
EOF
    )
    pytool login_vm_and_run_cmds gg "${cmd[*]}"

    local q_num=$1
    local hw_vlan_flag="--disable-hw-vlan"
    local legacy_mem=""

    local cmd_test="testpmd -l 0,1,2  \
    --socket-mem 1024 \
    ${legacy_mem} \
    -n 4 \
    -- \
    --forward-mode=macswap \
    --port-topology=chained \
    ${hw_vlan_flag} \
    --disable-rss \
    -i \
    --rxq=${q_num} \
    --txq=${q_num} \
    --rxd=256 \
    --txd=256 \
    --nb-cores=2 \
    --auto-start"

    pytool login_vm_and_run_cmds gg "${cmd_test}"
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
        dpdk-devbind -s
    fi
    return 0
}

clear_env()
{
    systemctl start openvswitch
    ovs-vsctl --if-exists del-br ovsbr0
    virsh destroy gg
    virsh undefine gg
    systemctl stop openvswitch
    rlRun clear_trex
    clear_dpdk_interface
    clear_hugepage
    return 0
}

bonding_test_trex()
{
    local t_time=$1
    local pkt_size=$2
    pushd $CASE_PATH
    #get trex server ip 
    rm -f /tmp/conn_is_ok
    timeout -s SIGINT 3 ping $TRAFFICGEN_TREX_HOST_IP_ADDR -c 3 > /tmp/conn_is_ok
    loss_check=`grep packets /tmp/conn_is_ok | awk '{print $6}'`
    if [ "${loss_check::-1}" == "100" ];then
            echo "trex server "$TRAFFICGEN_TREX_HOST_IP_ADDR" is no up "
    else
            install_rpms
            init_python_env
    fi
    #first use short time quick find the near value and test it long it to find is there any packet loss.
    local trex_dir=`basename .tar.gz $TREX_URL`
    local trex_name=`basename $TREX_URL`
    [ -d $trex_dir ] || wget $TREX_URL > /dev/null 2>&1
    [ -d $trex_dir ] || tar -xvf $trex_name > /dev/null 2>&1
    loginfo "python ./trex_sport.py -c $TRAFFICGEN_TREX_HOST_IP_ADDR -t $t_time --pkt_size=${pkt_size} -m 10"
    python ./trex_sport.py -c $TRAFFICGEN_TREX_HOST_IP_ADDR -t $t_time --pkt_size=${pkt_size} -m 10

    popd
    return 0
}

update_xml_vhostuser()
{
    pytool remove_item_from_xml g1.xml "./devices/interface[@type='vhostuser']" 

    local item=$(
    cat <<EOF
    <interface type='vhostuser'>
        <mac address={}'/>
        <source type='unix' path={} mode='server'/>
        <model type='virtio'/>
        <driver name='vhost' iommu='on' ats='on'/>
        <address type='pci' domain={} bus={} slot={} function={}/>
    </interface>
EOF    
    )

    local format_list=('52:54:00:11:8f:ea' '/tmp/vhost0' '0x0000' '0x03' '0x0' '0x0')
    local format_item=`pytool format_item $item "${format_list[@]}"`
    pytool add_item_from_xml g1.xml "./devices" "$format_item"

    local format_list_1=('52:54:00:11:8f:eb' '/tmp/vhost1' '0x0000' '0x04' '0x0' '0x0')
    local format_item_1=`pytool format_item $item "${format_list_1[@]}"`
    pytool add_item_from_xml g1.xml "./devices" "$format_item"

}


run_tests() 
{
    TESTLIST=$1

    if [ "$TESTLIST" == "pvp_cont" ];then
        echo "*** Running 1500 Byte PVP VSPerf verify check ***"
        echo "*** For 1Q 2PMD Test"

        loginfo "Clean Env Now Begin"
        clearn_env

        local nic1_mac=`pytool get_mac_from_name $NIC1`
        local nic2_mac=`pytool get_mac_from_name $NIC2` 
        enable_dpdk $nic1_mac $nic2_mac

        ovs_bridge_with_dpdk "${nic1_mac}" "${nic2_mac}" 1500 "${PMD2MASK}"
        local numa_node=`cat /sys/class/net/${NIC1}/device/numa_node`
        local vcpu_list=($VCPU1 $VCPU2 $VCPU3)
        
        vcpupin_in_xml $numa_node guest.xml g1.xml $vcpu_list

        update_xml_vhostuser

        pytool update_image_source g1.xml ${CASE_PATH}/${one_queue_image}

        start_guest g1.xml 

        configure_guest

        guest_start_testpmd


        bonding_test_trex
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

usage () {
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

install_rpms
init_python_env


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

enable_dpdk
ovs_bridge_with_dpdk
vcpupin_in_xml
start_guest
destroy_guest
configure_guest
guest_start_testpmd
clear_dpdk_interface
clear_env
bonding_test_trex

run_tests $TESTLIST
print_results
copy_config_files_to_log_folder
}

if [ "${1}" != "--source-only" ]
then
    main "${@}"
fi
