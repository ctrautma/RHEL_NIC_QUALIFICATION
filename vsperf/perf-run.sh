#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: replace vsperf with this file
#   Author: Hekai Wang <hewang@redhat.com>
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

# Main file . Please first config the below item and then run this file

#######################################################################
# NIC Device names such as p6p1 p6p2
NIC1=""
NIC2=""

# PMD CPUS 
# Example with a layout such as seen from the output cpu_layout.py
# python cpu_layout.py
# ======================================================================
# Core and Socket Information (as reported by '/sys/devices/system/cpu')
# ======================================================================
#
# cores =  [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13]
# sockets =  [0, 1]
#
#         Socket 0        Socket 1
#         --------        --------
# Core 0  [0, 24]         [1, 25]
# Core 1  [2, 26]         [3, 27]
# Core 2  [4, 28]         [5, 29]
# Core 3  [6, 30]         [7, 31]
# Core 4  [8, 32]         [9, 33]
# Core 5  [10, 34]        [11, 35]
# Core 8  [12, 36]        [13, 37]
# Core 9  [14, 38]        [15, 39]
# Core 10 [16, 40]        [17, 41]
# Core 11 [18, 42]        [19, 43]
# Core 12 [20, 44]        [21, 45]
# Core 13 [22, 46]        [23, 47]

# To user 44,20 ,if your NIC is on Numa 0 you would use PMD_CPU_1=44 PMD_CPU2=20
# To use cores 44,20 and 42,18 I would use  PMD_CPU_1=44 PMD_CPU2=20 PMD_CPU3=42 PMD_CPU4=18

PMD_CPU_1=""
PMD_CPU_2=""
PMD_CPU_3=""
PMD_CPU_4=""

# Virtual NIC Guest CPU Binding
# Using the same scripts above assign first VCPU to a single core. Then assign
# VCPU2 and VCPU3 to a core/HT pair such as 4,28. Should not be a core already
# in use by the PMD MASK. All CPU assignments should be on different
# Hyperthreads.

VCPU1=""
VCPU2=""
VCPU3=""

# Will need additional VCPUs for 2 queue test 
VCPU4=""
VCPU5=""


# TESTPMD descriptor size, can be used to modify descriptor sizes inside of VM when running TESTPMD for dpdk and kernel
# vsperf tests. SR-IOV options can be used to modify sr-iov descriptor sizes
TXD_SIZE=512
RXD_SIZE=512
SRIOV_TXD_SIZE=2048
SRIOV_RXD_SIZE=2048

# Update your Trex trafficgen info below
TRAFFICGEN_TREX_HOST_IP_ADDR=''

# Mac addresses of the ports configured in TRex Server
TRAFFICGEN_TREX_PORT1=''
TRAFFICGEN_TREX_PORT2=''

#SR-IOV Information
# To run SR-IOV tests please complete the following info
# NIC Device name for VF on NIC1 and NIC2 Example p6p1_0 for vf0 on p6p1
NIC1_VF=""
NIC2_VF=""

#config end 
################################################################################

CASE_PATH=$(dirname $(readlink -f $0))

source /etc/os-release || exit 1

SYSTEM_VERSION_ID=`echo $VERSION_ID | tr -d '.'`

check_install()
{
	local pkg_name=$1
	echo "***************************************"
	rpm -q $pkg_name || yum -y install $pkg_name
	echo "***************************************"
	return 0
}

install_init_package()
{
    pushd $CASE_PATH
    [[ -d beakerlib ]] || rm -rf beakerlib

    local all_packs=(
        wget
        git
        gcc
        make
        bc
        lsof
        nmap-ncat
        tcpdump
        expect
	)
	for pack in "${all_packs[@]}"
	do
		check_install $pack
	done
	
	if (( $SYSTEM_VERSION_ID < 80 ))
    then
		check_install bridge-utils
	fi

	#install beakerlib
	if ! [[ -f /usr/share/beakerlib/beakerlib.sh ]]
	then
		git clone https://github.com/beakerlib/beakerlib
		pushd beakerlib
            git checkout beakerlib-1.18
            make
            make install
		popd
	fi

    popd
}



if [[ $CUSTOMER_PFT_TEST == "yes" ]]
then
	CASE_PATH=${CASE_PATH:-"$(dirname $(readlink -f $0))"}
	need_all_packs=(
		wget
		git
		gcc
		make
		bc
		lsof
		nmap-ncat
		tcpdump
		expect
	)
	for pack in "${need_all_packs[@]}"
	do
		check_install $pack
	done
	
	if (( $SYSTEM_VERSION_ID < 80 ))
    then
		check_install bridge-utils
	fi

	#install beakerlib
	if ! [[ -f /usr/share/beakerlib/beakerlib.sh ]]
	then
		rm -rf beakerlib
		git clone https://github.com/beakerlib/beakerlib
		pushd beakerlib
		make
		make install
		popd
	fi
else
	CASE_PATH=${CASE_PATH:-"/mnt/tests//kernel/networking/vnic/sriov_dpdk_pft"}
fi

source env.sh || exit 1
source lib/lib_nc_sync.sh || exit 1
source lib/lib_utils.sh || exit 1
source /usr/share/beakerlib/beakerlib.sh || exit 1

add_repo_rhel7()
{
	rpm --import "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF"
	local tuned_repo=(
			"[tuned]"
			"name=Tuned development repository for RHEL-7"
			"baseurl=https://fedorapeople.org/~jskarvad/tuned/devel/repo/"
			"enabled=1"
			"gpgcheck=0"
			"skip_if_unavailable=1"
	)
	printf "%s\n" "${tuned_repo[@]}" >> /etc/yum.repos.d/tuned.repo
	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	cp --remove-destination rhos-release-13.repo /etc/yum.repos.d/
}

install_package()
{
	if (( $SYSTEM_VERSION_ID < 80 ))
    then
		add_repo_rhel7
		yum -y install qemu-img-rhev 
		yum -y install qemu-kvm-common-rhev
		yum -y install qemu-kvm-rhev 
		yum -y install qemu-kvm-tools-rhev
	else
		yum install -y qemu-img 
		yum -y install qemu-kvm 
		yum -y install platform-python-devel
    fi

	local all_pack=(
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
		python
		czmq-devel
		libguestfs-tools
		ethtool
		libvirt-devel
		libvirt-python
		python3-lxml
		emacs 
		gcc 
		git 
		lshw 
		pciutils 
		python-devel 
		python-setuptools 
		python-pip
	)

	for pack in "${all_pack[@]}"
	do
		check_install $pack
	done

	#for qemu bug that can not start qemu
	if (( $SYSTEM_VERSION_ID < 80 ))
	then
		echo -e "group = 'hugetlbfs'" >> /etc/libvirt/qemu.conf
	fi
	
	systemctl restart libvirtd
	systemctl start virtlogd.socket
	
	# work around for failure of virt-install
	chmod 666 /dev/kvm

}

#get nic name from mac address
function get_nic_name_from_mac()
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
	export PYTHONPATH=${CASE_PATH}/venv/lib64/python3.6/site-packages/
    pip install --upgrade pip

	pip install fire
	pip install psutil
	pip install paramiko
    pip install xmlrunner
	pip install netifaces
	pip install argparse
	pip install plumbum
	pip install ethtool
	pip install shell
}

get_pmd_masks()
{
    local cpus=$1
    local pmd_mask
    temp_array=($cpus)
    temp_len=${#temp_array[@]}
    last_cpu_1=`echo ${temp_array[$temp_len-1]}`
    last_cpu_2=${temp_array[$temp_len-2]}
    sibling_cpu_1=`cat /sys/devices/system/cpu/cpu$last_cpu_1/topology/thread_siblings_list | awk -F ',' '{print $1}'`
    sibling_cpu_2=`cat /sys/devices/system/cpu/cpu$last_cpu_2/topology/thread_siblings_list | awk -F ',' '{print $1}'`
    pmd_mask=`python tools.py get-pmd-masks "$last_cpu_1 $last_cpu_2 $sibling_cpu_1 $sibling_cpu_2"`
    echo $pmd_mask
}

get_isolate_cpus()
{
    local nic_name=$1
    local ISOLCPUS_SERVER
    ISOLCPUS_SERVER=`python tools.py get-isolate-cpus-with-nic $nic_name`
	echo $ISOLCPUS_SERVER
}

install_dpdk()
{
    rpm -ivh ${DPDK_URL}
    rpm -ivh ${DPDK_TOOL_URL}
}

config_hugepage()
{
    local server_cpu
    local client_cpu
    server_cpu=${ISOLCPUS_SERVER//' '/,}
    client_cpu=${ISOLCPUS_CLIENT//' '/,}

	if (( $SYSTEM_VERSION_ID >= 80 ))
	then
        sed -i s/GRUB_ENABLE_BLSCFG/\#GRUB_ENABLE_BLSCFG/g /etc/default/grub
    fi

	if i_am_server; then
	        echo -e "isolated_cores=$server_cpu" >> /etc/tuned/cpu-partitioning-variables.conf
	        tuned-adm profile cpu-partitioning
	        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="isolcpus='"$server_cpu"' ${GRUB_CMDLINE_LINUX_DEFAULT:+$GRUB_CMDLINE_LINUX_DEFAULT }\\$tuned_params"' /etc/default/grub
	fi
	if i_am_client; then
	        echo -e "isolated_cores=$client_cpu" >> /etc/tuned/cpu-partitioning-variables.conf
	        tuned-adm profile cpu-partitioning
	        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="isolcpus='"$client_cpu"' ${GRUB_CMDLINE_LINUX_DEFAULT:+$GRUB_CMDLINE_LINUX_DEFAULT }\\$tuned_params"' /etc/default/grub
	fi
	sed -i 's/\(GRUB_CMDLINE_LINUX.*\)"$/\1/g' /etc/default/grub
	if [ $NIC_DRIVER == "qede" ];then
	    sed -i "s/GRUB_CMDLINE_LINUX.*/& nohz=on default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr \"/g" /etc/default/grub
	else
	    sed -i "s/GRUB_CMDLINE_LINUX.*/& nohz=on default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\"/g" /etc/default/grub
	fi
	grub2-mkconfig -o /boot/grub2/grub.cfg
	rhts-reboot
	cat /proc/cmdline
}

function init_test_env()
{
    if i_am_server;then
        local SERVER_NIC1_NAME=`get_nic_name_from_mac $SERVER_NIC1_MAC`
        SERVER_NUMA=$(cat /sys/class/net/${SERVER_NIC1_NAME}/device/numa_node)
        ISOLCPUS_SERVER=`get_isolate_cpus "$SERVER_NIC1_NAME"`
        SERVER_PMD_CPU_MASK=`get_pmd_masks "$ISOLCPUS_SERVER"`
    elif i_am_client;then
        local CLIENT_NIC1_NAME=`get_nic_name_from_mac $CLIENT_NIC1_MAC`
        CLIENT_NUMA=$(cat /sys/class/net/${CLIENT_NIC1_NAME}/device/numa_node)
        ISOLCPUS_CLIENT=`get_isolate_cpus "${CLIENT_NIC1_NAME}"`
        CLIENT_PMD_CPU_MASK=`get_pmd_masks "$ISOLCPUS_CLIENT"`
    else
        echo "error server role"
        true
    fi

    echo "SERVER NUMA IS "$SERVER_NUMA
    echo "SERVER ISOLATED CPUS IS "$ISOLCPUS_SERVER
    echo "SERVER PMD CPU MASK IS "$SERVER_PMD_CPU_MASK
    echo "CLIENT NUMA IS "$CLIENT_NUMA
    echo "CLIENT ISOLATED CPUS IS "$ISOLCPUS_CLIENT
    echo "CLIENT PMD CPU MASK IS "$CLIENT_PMD_CPU_MASK
}

install_driverctl()
{
    yum install -y ${DRIVERCTL_URL}
}

enable_dpdk()
{
	pushd $CASE_PATH
    install_dpdk
    install_driverctl
    local nic1_mac=$1
    local nic2_mac=$2
    local nic1_name=`python lib_sriov.py sriov_get_nic_name_from_mac $nic1_mac`
    local nic2_name=`python lib_sriov.py sriov_get_nic_name_from_mac $nic2_mac`
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
        #return 0
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
	popd
}

cpu_list_on_numa()
{
        local numa_node=${1:-0}
        local cpulist=""
        local i=""
        local CPU=""

        CPU=$(lscpu | grep "NUMA node${numa_node} CPU(s):" | awk '{print $NF}')
        CPU=$(echo -n $CPU | sed 's/,/ /g' | sed s/-/../g)

        for i in $CPU
        do
                echo $i | grep '\.\.' > /dev/null && \
                cpus=$(
                        bash -c "
                                list=''
                                for i in {$i}
                                do
                                        [ -z \"\$list\" ] && list="\$i" || list+=\" \$i\"
                                done
                                echo \$list
                ") || cpus="$i "
                [ -z "$cpulist" ] && cpulist=$cpus || cpulist+=" $cpus"
        done
        echo -n $cpulist
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
	popd 1>/dev/null
}


start_guest()
{
    systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd

	local image_name=`basename ${IMAGE_GUEST}`
	
	[[ -f /root/rhel.qcow2 ]] && rm -f /root/rhel.qcow2
	wget -P /root/ ${IMAGE_GUEST} > /dev/null 2>&1
	pushd /root/
		mv $image_name rhel.qcow2
	popd
	chmod 777 /root/
	local udev_file=60-persistent-net.rules
	touch $udev_file
    cat > $udev_file <<EOF
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:02:00.0", NAME:="eth0"
EOF

	virt-copy-in -a /root/rhel.qcow2 $udev_file /etc/udev/rules.d/
	#Here add dpdk rpm to guest
	rm -rf /root/${DPDK_VERSION}
	mkdir -p /root/${DPDK_VERSION}
	wget -P /root/${DPDK_VERSION}/ ${DPDK_URL}      > /dev/null 2>&1
	wget -P /root/${DPDK_VERSION}/ ${DPDK_TOOL_URL} > /dev/null 2>&1
	virt-copy-in -a /root/rhel.qcow2 /root/${DPDK_VERSION}/ /root/
	sleep 5
	virsh define ${CASE_PATH}/g1.xml
	chmod 777 /root/
	virsh start guest30032
}

destroy_guest()
{
    virsh destroy guest30032
    virsh undefine guest30032
}

configure_guest()
{
	local cmd=(
            {nmcli dev set eth0 managed no}
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
			{pkill dhclient}
			{dhclient -v eth0}
            {ip -d addr show}
                )

	vmsh cmd_set guest30032 "${cmd[*]}"
}


guest_bind_dpdk()
{
	{dpdk-devbind -b vfio-pci 0000:03:00.0}
	{dpdk-devbind -b vfio-pci 0000:04:00.0}
}


#{modprobe  vfio enable_unsafe_noiommu_mode=1}
guest_start_testpmd()
{
	local vf1_bus=$1
	local vf2_bus=$2
	local pkt_size=$3

    local cmd=(
        {/root/one_gig_hugepages.sh 1}
		{rpm -ivh  /root/$DPDK_VERSION/dpdk*.rpm}
        {modprobe -r vfio_iommu_type1}
        {modprobe -r vfio}
        {modprobe  vfio }
        {modprobe vfio-pci}
        {ip link set eth1 down}
        {dpdk-devbind -b vfio-pci $vf1_bus}
		{dpdk-devbind -b vfio-pci $vf2_bus}
        {dpdk-devbind --status}
        )

    vmsh cmd_set guest30032 "${cmd[*]}"

    local q_num=1
    local guest_dpdk_ver=`echo $DPDK_VERSION | awk -F '-' '{print $1}' | tr -d '.'`
    local hw_vlan_flag=""

    if (( $guest_dpdk_ver >= 1811 ))
    then
        hw_vlan_flag=""
    else
        hw_vlan_flag="--disable-hw-vlan"
    fi

    #VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd guest30032 "testpmd -l 0,1,2 --legacy-mem --socket-mem 1024 -n 4 -- --forward-mode=io --port-topology=chained ${hw_vlan_flag} --disable-rss -i --rxq=${q_num} --txq=${q_num} --rxd=256 --txd=256 --nb-cores=2 --max-pkt-len=9600 --auto-start"
	VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd guest30032 "testpmd -l 0,1,2 --legacy-mem --socket-mem 1024 -n 4 -- --forward-mode=io  ${hw_vlan_flag} --disable-rss -i --rxq=${q_num} --txq=${q_num} --rxd=256 --txd=256 --nb-cores=2  --max-pkt-len=${pkt_size} --auto-start"
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
	rlLog "Clear dpdk binded interface from vfio-pci driver to kernel driver"
	if rpm -qa | grep dpdk-tools
    then
		dpdk-devbind -s
		echo "*******************************************************************"
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
    virsh destroy guest30032
    virsh undefine guest30032
    rlRun clear_trex
    rlRun clear_dpdk_interface
    rlRun clear_hugepage

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
	local pkt_size=$1
	local vlan_flag=$2
	local dst_mac=$3
    pushd $CASE_PATH
    #get trex server ip 
    rm -f /tmp/conn_is_ok
    timeout -s SIGINT 3 ping $TREX_SERVER_IP -c 3 > /tmp/conn_is_ok
    loss_check=`grep packets /tmp/conn_is_ok | awk '{print $6}'`
    if [ "${loss_check::-1}" == "100" ];then
            echo "trex server "$TREX_SERVER_IP" is no up "
    else
		install_package
		init_python_env
		update_ssh_trust
    fi
    #first use short time quick find the near value and test it long it to find is there any packet loss.
    local trex_dir=`basename .tar.gz $TREX_URL`
    local trex_name=`basename $TREX_URL`
    [ -d $trex_dir ] || wget $TREX_URL > /dev/null 2>&1
    [ -d $trex_dir ] || tar -xvf $trex_name > /dev/null 2>&1
    #rlRun "python ./trex_sport.py -c $TREX_SERVER_IP -t 60 --pkt_size=$pkt_size -m 10 -v $vlan_flag"
	if [[ $vlan_flag != 0 ]]
	then
		rlRun "python ./trex_sport.py -c $TREX_SERVER_IP -t 60 --pkt_size=$pkt_size -m 10 -v $vlan_flag -d \"$dst_mac\" "
	else
		rlRun "python ./trex_sport.py -c $TREX_SERVER_IP -t 60 --pkt_size=$pkt_size -m 10  -d \"$dst_mac\" "
	fi
    popd
    return 0
}


install_trex_and_start()
{
    local nic1_mac=$1
    local nic2_mac=$2
    local trex_url=$3
    pushd $CASE_PATH

    install_dpdk
    install_driverctl
 
    trex_name=`basename ${trex_url}`
    trex_dir=`basename -s .tar.gz ${trex_url}`
    [ -d ${trex_dir} ] || wget ${trex_url} > /dev/null 2>&1
    [ -d ${trex_dir} ] || tar -xvf $trex_name > /dev/null 2>&1
    pushd $trex_dir
    local nic1_name=`get_nic_name_from_mac $nic1_mac`
    local nic2_name=`get_nic_name_from_mac $nic2_mac`
    local nic1_bus=`ethtool -i $nic1_name | grep bus-info | awk '{print $NF}'`
    local nic2_bus=`ethtool -i $nic2_name | grep bus-info | awk '{print $NF}'`
    local nic_bus="$nic1_bus $nic2_bus"
    rm -f /etc/trex_cfg.yaml
    ./dpdk_setup_ports.py -c $nic_bus --force-macs --no-ht -o /etc/trex_cfg.yaml
    local isolate_cpus=`grep threads /etc/trex_cfg.yaml  | awk '{print $NF}' | tr -d []`

    systemctl enable tuned
    systemctl start tuned
	

    enable_dpdk $nic1_mac $nic2_mac
    ./trex_daemon_server restart
    sleep 10
    popd
    
    popd
}

clear_hugepage()
{
    local hugepage_dir=`mount -l | grep hugetlbfs | awk '{print $3}'`
    rlRun "rm -rf $hugepage_dir/*"
    return 0
}

clear_trex()
{
    rlRun "pkill t-rex-64" "0,1"
    rlRun "pkill t-rex-64" "0,1"
    rlRun "pkill _t-rex-64" "0,1"
    rlRun "pkill _t-rex-64" "0,1"
    return 0
}

clear_trex_and_free_hugepage()
{
    clear_trex
    clear_hugepage
    return 0
}


# set up env
sriov_setup()
{
	# stop security features
	if (($rhel_version >= 7))
	then
		systemctl stop NetworkManager
		systemctl stop firewalld
	fi
	iptables -F
	ip6tables -F
	systemctl stop firewalld

	# prepare VMs
	echo "Download guest image..."

	# define default vnet
	virsh net-define /usr/share/libvirt/networks/default.xml
	virsh net-start default
	virsh net-autostart default

	start_guest
	configure_guest

	return 0
}

init_spec_driver_config()
{
	yum install -y libibverbs
#	echo options mlx4_core log_num_mgm_entry_size=-1  >> /etc/modprobe.d/mlx4.conf
#	dracut -f -v
#	mkdir -p /mnt/huge
#	mount -t hugetlbfs nodev /mnt/huge
}

host_start_testpmd()
{
	local forward_mode=io
	forward_mode=$1
	local bus1=$2
	local bus2=$3
	local pkt_size=$4

	local q_num=1
	local dpdk_ver=`basename $DPDK_URL | awk -F '-' '{print $2}' | tr -d '.'`
	local hw_vlan_flag=""
	if (( $dpdk_ver >= 1811))
	then
		hw_vlan_flag=""
	else
		hw_vlan_flag="--disable-hw-vlan"
	fi
	pkill testpmd
	sleep 10

	if [[ $pkt_size -le 1500 ]]
	then
		pkt_size=1500
	fi
	# local socket_mem_info=""
	# numa_num=`lscpu | grep 'NUMA node(s)' | awk  '{print $NF}'`
	# for i in `seq $numa_num`
	# do
	# 	socket_mem_info=$socket_mem_info" 1024"
	# done
	#here we need config with numa 
	#--max-pkt-len=9600 \
	local cpu_info=`tail -n 1 /etc/tuned/cpu-partitioning-variables.conf | awk -F '=' '{print $NF}' | cut -d ',' -f 1-3`
	tail -f /dev/null | testpmd -l $cpu_info -w $bus1 -w $bus2 --socket-mem 1024 --legacy-mem -n 4  -- -i \
	--forward-mode=${forward_mode} \
	${hw_vlan_flag} \
	--disable-rss \
	--rxq=${q_num} \
	--txq=${q_num} \
	--rxd=256 \
	--txd=256 \
	--nb-cores=2 \
	--max-pkt-len=${pkt_size} \
	--auto-start &

	sleep 20
}

server_host_link_up()
{
	local pkt_size=$1
	local nic1_name="nic_error"
	local nic2_name="nic_error"
	nic1_name=`get_nic_name_from_mac $SERVER_NIC1_MAC`
	nic2_name=`get_nic_name_from_mac $SERVER_NIC2_MAC`
	ip li set $nic1_name up 
	ip li set $nic2_name up
	if [[ $pkt_size -ge 1500 ]]
	then
		ip link set dev $nic1_name mtu $pkt_size 
		ip link set dev $nic2_name mtu $pkt_size 
	else
		ip link set dev $nic1_name mtu 1500 
		ip link set dev $nic2_name mtu 1500		
	fi
	return 0
}

client_host_link_up()
{
	local pkt_size=$1
	local nic1_name="nic_error"
	local nic2_name="nic_error"
	nic1_name=`get_nic_name_from_mac $CLIENT_NIC1_MAC`
	nic2_name=`get_nic_name_from_mac $CLIENT_NIC2_MAC`
	ip li set $nic1_name up 
	ip li set $nic2_name up
	if [[ $pkt_size -ge 1500 ]]
	then
		ip link set dev $nic1_name mtu $pkt_size 
		ip link set dev $nic2_name mtu $pkt_size 
	else
		ip link set dev $nic1_name mtu 1500 
		ip link set dev $nic2_name mtu 1500		
	fi
	return 0
}

init_host_pf_env()
{
	if i_am_server;then
		local nic1_name="nic_error"
		local nic2_name="nic_error"
		nic1_name=`get_nic_name_from_mac $SERVER_NIC1_MAC`
		nic2_name=`get_nic_name_from_mac $SERVER_NIC2_MAC`
		local nic1_bus=`python lib_sriov.py sriov_get_bus_from_name $nic1_name`
		local nic2_bus=`python lib_sriov.py sriov_get_bus_from_name $nic2_name`
		export SERVER_NIC1_BUS=$nic1_bus
		export SERVER_NIC2_BUS=$nic2_bus
	else
		local client_nic1_name=`get_nic_name_from_mac $CLIENT_NIC1_MAC`
		local client_nic2_name=`get_nic_name_from_mac $CLIENT_NIC2_MAC`
		local client_nic1_bus=`python lib_sriov.py sriov_get_bus_from_name $client_nic1_name`
		local client_nic2_bus=`python lib_sriov.py sriov_get_bus_from_name $client_nic2_name`
		export CLIENT_NIC1_BUS=$client_nic1_bus
		export CLIENT_NIC2_BUS=$client_nic2_bus
	fi
	return 0
}

###############################
sriov_test_testpmd_loopback()
{
	local func_name=${FUNCNAME[0]}
	rlLog "$func_name Test begin "


	if i_am_server;then
		#set link up
		server_host_link_up 64

		init_host_pf_env

		#enable dpdk with nic
		enable_dpdk $SERVER_NIC1_MAC $SERVER_NIC2_MAC

		sync_wait client CLIENT_TREX_STARTED
		#start testpmd with dpdk nic
		host_start_testpmd "io" $SERVER_NIC1_BUS $SERVER_NIC2_BUS 64

		bonding_test_trex 64 0 "$SERVER_NIC1_MAC $SERVER_NIC2_MAC"

		# pid_testpmd=`pidof testpmd | tr -d ' ' | tr -d '\r\n'`
		# echo "show port info all" > /proc/${pid_testpmd}/fd/0
		# echo "show port stats all" > /proc/${pid_testpmd}/fd/0

		pkill -f -x -9 'tail -f /dev/null'
		pkill testpmd
		sync_set client SERVER_TEST_FINISHED
	else
		#set client side link up 
		client_host_link_up 64

		install_trex_and_start $CLIENT_NIC1_MAC $CLIENT_NIC2_MAC ${TREX_URL}

		sync_set server CLIENT_TREX_STARTED
		sync_wait server SERVER_TEST_FINISHED

	fi
}

sriov_test_pf_remote()
{
	local pkt_size=$1
	local vlan_flag=$2
	local func_name=${FUNCNAME[0]}
	rlLog "$func_name Test begin : pkt_size "$pkt_size" "


	if i_am_server;then
		#set link up
		server_host_link_up $pkt_size

		init_host_pf_env
		
		#enable dpdk with nic
		enable_dpdk $SERVER_NIC1_MAC $SERVER_NIC2_MAC

		sync_wait client CLIENT_TREX_STARTED

		#start testpmd with dpdk nic
		host_start_testpmd "io" $SERVER_NIC1_BUS $SERVER_NIC2_BUS $pkt_size

		bonding_test_trex $pkt_size $vlan_flag "$SERVER_NIC1_MAC $SERVER_NIC2_MAC"

		# pid_testpmd=`pidof testpmd | tr -d ' ' | tr -d '\r\n'`
		# echo "show port info all" > /proc/${pid_testpmd}/fd/0
		# echo "show port stats all" > /proc/${pid_testpmd}/fd/0

		pkill -f -x -9 'tail -f /dev/null'
		pkill testpmd
		sync_set client SERVER_TEST_FINISHED
	else
		#set client side link up 
		client_host_link_up $pkt_size

		install_trex_and_start $CLIENT_NIC1_MAC $CLIENT_NIC2_MAC ${TREX_URL}

		sync_set server CLIENT_TREX_STARTED
		sync_wait server SERVER_TEST_FINISHED

	fi
}

sriov_test_pf_all()
{
	sriov_test_pf_remote 64 0
	clear_env
	sriov_test_pf_remote 9000 0
	clear_env
	sriov_test_pf_remote 64 1
	clear_env
	sriov_test_pf_remote 9000 1
	clear_env
	return 0 
}

sriov_test_vf_remote()
{
	local pkt_size=$1
	local vlan_flag=$2
	local func_name=${FUNCNAME[0]}
	rlLog "$func_name Test begin : packet size "$pkt_size" vlan flag "$vlan_flag
	local vf_name=""

	if i_am_server;then
		#set link up
		server_host_link_up $pkt_size
		
		local nic1_name=`get_nic_name_from_mac $SERVER_NIC1_MAC`
		local nic2_name=`get_nic_name_from_mac $SERVER_NIC2_MAC`		
		local nic1_bus=`python lib_sriov.py get_pf_bus_from_pf_name $nic1_name`
		local nic2_bus=`python lib_sriov.py get_pf_bus_from_pf_name $nic2_name`
		
		#create one vf for each pf nic
		python lib_sriov.py sriov_create_vfs --pf-bus $nic1_bus --num 1
		python lib_sriov.py sriov_create_vfs --pf-bus $nic2_bus --num 1

		local vf1_name=`python lib_sriov.py sriov_get_vf_name_from_pf $nic1_name`
		local vf2_name=`python lib_sriov.py sriov_get_vf_name_from_pf $nic2_name`
		local vf1_mac=`python lib_sriov.py sriov_get_mac_from_name $vf1_name`
		local vf2_mac=`python lib_sriov.py sriov_get_mac_from_name $vf2_name`
		
		local random_addr=""
		if [[ $vf1_mac == "00:00:00:00:00:00" ]]
		then
			random_addr=`python lib_sriov.py get_random_mac_addr`
			ip li set $nic1_name up 
			ip li set $vf1_name up 
			ip li set $vf1_name address $random_addr			
		fi

		if [[ $vf2_mac == "00:00:00:00:00:00" ]]
		then
			random_addr=`python lib_sriov.py get_random_mac_addr`
			ip li set $nic2_name up 
			ip li set $vf2_name up 
			ip li set $vf2_name address $random_addr			
		fi
		#again get vf mac for enable dpdk 
		vf1_mac=`python lib_sriov.py sriov_get_mac_from_name $vf1_name`
		vf2_mac=`python lib_sriov.py sriov_get_mac_from_name $vf2_name`

		#here avoid testpmd make mac address change 
		ip li set $nic1_name vf 0 mac $vf1_mac
		ip li set $nic2_name vf 0 mac $vf2_mac

		local vf1_bus=`python lib_sriov.py sriov_get_bus_from_name $vf1_name`
		local vf2_bus=`python lib_sriov.py sriov_get_bus_from_name $vf2_name`

		ip li set $nic1_name vf 0 spoofchk off
		ip li set $nic2_name vf 0 spoofchk off
  		ip li set $nic1_name vf 0 trust on 
		ip li set $nic2_name vf 0 trust on 
		#enable dpdk with nic
		enable_dpdk $vf1_mac $vf2_mac

		sync_wait client CLIENT_TREX_STARTED

		#start testpmd with dpdk nic
		host_start_testpmd "io" $vf1_bus $vf2_bus $pkt_size


		bonding_test_trex $pkt_size $vlan_flag "$vf1_mac $vf2_mac"

		# pid_testpmd=`pidof testpmd | tr -d ' ' | tr -d '\r\n'`
		# echo "show port info all" > /proc/${pid_testpmd}/fd/0
		# echo "show port stats all" > /proc/${pid_testpmd}/fd/0
		pkill -f -x -9 'tail -f /dev/null'
		pkill testpmd
		sync_set client SERVER_TEST_FINISHED

	else
		#set client side link up 
		client_host_link_up
		install_trex_and_start $CLIENT_NIC1_MAC $CLIENT_NIC2_MAC ${TREX_URL}
		sync_set server CLIENT_TREX_STARTED
		sync_wait server SERVER_TEST_FINISHED
	fi
}

sriov_test_vf_all()
{
	sriov_test_vf_remote 64 0
	clear_env
	sriov_test_vf_remote 9000 0
	clear_env
	sriov_test_vf_remote 64 1
	clear_env
	sriov_test_vf_remote 9000 1
	clear_env
	return 0
}


sriov_test_vmvf_remote()
{
	local pkt_size=$1
	local vlan_flag=$2
	local func_name=${FUNCNAME[0]}
	rlLog "$func_name Test begin : packet size "$pkt_size" vlan flag "$vlan_flag
	local vf_name=""

		if i_am_server;then
		set -x
		#set link up
		server_host_link_up $pkt_size

		vcpupin_in_xml $SERVER_NUMA $SERVER_VCPUS guest.xml g1.xml server
        start_guest
        configure_guest
		
		local nic1_name=`get_nic_name_from_mac $SERVER_NIC1_MAC`
		local nic2_name=`get_nic_name_from_mac $SERVER_NIC2_MAC`		
		local nic1_bus=`python lib_sriov.py sriov_get_pf_bus_from_pf_name $nic1_name`
		local nic2_bus=`python lib_sriov.py sriov_get_pf_bus_from_pf_name $nic2_name`
		
		#create one vf for each pf nic
		python lib_sriov.py sriov_create_vfs --pf-bus $nic1_bus --num 1
		python lib_sriov.py sriov_create_vfs --pf-bus $nic2_bus --num 1

		local vf1_name=`python lib_sriov.py sriov_get_vf_name_from_pf $nic1_name`
		local vf2_name=`python lib_sriov.py sriov_get_vf_name_from_pf $nic2_name`
		local vf1_mac=`python lib_sriov.py sriov_get_mac_from_name $vf1_name`
		local vf2_mac=`python lib_sriov.py sriov_get_mac_from_name $vf2_name`
		
		local random_addr=""
		if [[ $vf1_mac == "00:00:00:00:00:00" ]]
		then
			random_addr=`python lib_sriov.py get_random_mac_addr`
			ip li set $nic1_name up 
			ip li set $vf1_name up 
			ip li set $vf1_name address $random_addr			
		fi

		if [[ $vf2_mac == "00:00:00:00:00:00" ]]
		then
			random_addr=`python lib_sriov.py get_random_mac_addr`
			ip li set $nic2_name up 
			ip li set $vf2_name up 
			ip li set $vf2_name address $random_addr			
		fi

		ip li set $nic1_name vf 0 spoofchk off
		ip li set $nic2_name vf 0 spoofchk off
  		ip li set $nic1_name vf 0 trust on 
		ip li set $nic2_name vf 0 trust on 

		local guest_name="guest30032"

		python lib_sriov.py sriov_attach_vf_to_vm $vf1_name $guest_name
		python lib_sriov.py sriov_attach_vf_to_vm $vf2_name $guest_name

		local temp_xml_file="cur_vm_xml_desc.xml"
		[[ -f $temp_xml_file ]] || rm -f $temp_xml_file
		virsh dumpxml $guest_name > $temp_xml_file

		local vf1_bus=`python tools.py get_pci_address_of_vm_hostdev $temp_xml_file 0`
		local vf2_bus=`python tools.py get_pci_address_of_vm_hostdev $temp_xml_file 1`
		#again get vf mac for trex use
		vf1_mac=`python tools.py get_mac_address_of_vm_hostdev $temp_xml_file 0`
		vf2_mac=`python tools.py get_mac_address_of_vm_hostdev $temp_xml_file 1`

		guest_start_testpmd $vf1_bus $vf2_bus $pkt_size

        sync_wait client CLIENT_TREX_STARTED

		bonding_test_trex $pkt_size $vlan_flag "$vf1_mac $vf2_mac"

		# pid_testpmd=`pidof testpmd | tr -d ' ' | tr -d '\r\n'`
		# echo "show port info all" > /proc/${pid_testpmd}/fd/0
		# echo "show port stats all" > /proc/${pid_testpmd}/fd/0
		pkill -f -x -9 'tail -f /dev/null'
		pkill testpmd
		sync_set client SERVER_TEST_FINISHED
		set +x

	else
		#set client side link up 
		client_host_link_up
		install_trex_and_start $CLIENT_NIC1_MAC $CLIENT_NIC2_MAC ${TREX_URL}
		sync_set server CLIENT_TREX_STARTED
		sync_wait server SERVER_TEST_FINISHED
	fi
}

sriov_test_vmvf_all()
{
	sriov_test_vmvf_remote 64 0
	clear_env
	sriov_test_vmvf_remote 9000 0
	clear_env
	sriov_test_vmvf_remote 64 1
	clear_env
	sriov_test_vmvf_remote 9000 1
	clear_env
	return 0
}


#######################
# main
rlJournalStart
rlPhaseStartSetup
if [[ ! -f /tmp/sriov_dpdk_pft ]]
then
    rlRun install_package
	rlRun install_dpdk
    rlRun init_python_env
    rlRun init_test_env
	rlRun "touch /tmp/sriov_dpdk_pft"
	rlRun config_hugepage
fi
rlPhaseEnd

rlPhaseStartTest "SRIOV DPDK PFT ENV INIT START"
if [[ -f /tmp/sriov_dpdk_pft ]]
then
    rlRun "cat /proc/cmdline"
    rlRun init_python_env
	rlRun clear_env
    rlRun init_test_env
	rlRun init_spec_driver_config
fi
rlPhaseEnd

if grep sriov_test_testpmd_loopback <<< "${ALL_CASE_LIST[@]}"
then
	rlPhaseStartTest "sriov test testpmd loopback mode"
	rlRun sriov_test_testpmd_loopback
	rlPhaseEnd

	rlPhaseStartTest "clear env "
	rlRun clear_env
	rlPhaseEnd
fi

if grep sriov_test_pf_all <<< "${ALL_CASE_LIST[@]}"
then
	rlPhaseStartTest "sriov_test_pf_remote"
	rlRun sriov_test_pf_all
	rlPhaseEnd

	rlPhaseStartTest "clear env "
	rlRun clear_env
	rlPhaseEnd
fi

if grep sriov_test_vf_all <<< "${ALL_CASE_LIST[@]}"
then
	rlPhaseStartTest "sriov_test_vf_remote"
	rlRun sriov_test_vf_all
	rlPhaseEnd

	rlPhaseStartTest "clear env "
	rlRun clear_env
	rlPhaseEnd
fi

if grep sriov_test_vmvf_all <<< "${ALL_CASE_LIST[@]}"
then
	rlPhaseStartTest "sriov_test_vmvf_remote"
	rlRun sriov_test_vmvf_all
	rlPhaseEnd

	rlPhaseStartTest "clear env "
	rlRun clear_env
	rlPhaseEnd

fi


rlJournalPrintText
rlJournalEnd



