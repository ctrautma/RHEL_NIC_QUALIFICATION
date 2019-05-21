#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/fd_nic_partition/no-bond
#   Author: Ting Li <tli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
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
# variables
# Include Beaker environment
. /mnt/tests/kernel/networking/common/include.sh || exit 1
. /mnt/tests/kernel/networking/common/lib/lib_nc_sync.sh || exit 1
. /mnt/tests/kernel/networking/common/lib/lib_netperf_all.sh || exit 1
. /mnt/tests/kernel/networking/fd_nic_partition/no-bond/lib_sriov.sh || exit 1

PACKAGE="kernel"
CASE_PATH="/mnt/tests/kernel/networking/fd_nic_partition/no-bond"
NAY=${NAY:-yes}
NIC_NUM=${NIC_NUM:-2}
#OVS_URL=${OVS_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.7.0/7.git20170530.el7fdb/x86_64/openvswitch-2.7.0-7.git20170530.el7fdb.x86_64.rpm}
#OVS_URL=${OVS_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.8.0/0.1.20170810git3631ed2.el7fdb/x86_64/openvswitch-2.8.0-0.1.20170810git3631ed2.el7fdb.x86_64.rpm}
OVS_URL=${OVS_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch/2.9.0/0.2.20171212git6625e43.el7fdb/x86_64/openvswitch-2.9.0-0.2.20171212git6625e43.el7fdb.x86_64.rpm}
#DPDK_URL=${DPDK_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/16.11.2/4.el7/x86_64/dpdk-16.11.2-4.el7.x86_64.rpm}
#DPDK_TOOL_URL=${DPDK_TOOL_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/16.11.2/4.el7/x86_64/dpdk-tools-16.11.2-4.el7.x86_64.rpm}
DPDK_URL=${DPDK_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/17.11/2.el7fdb/x86_64/dpdk-17.11-2.el7fdb.x86_64.rpm}
DPDK_TOOL_URL=${DPDK_TOOL_URL:-http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/17.11/2.el7fdb/x86_64/dpdk-tools-17.11-2.el7fdb.x86_64.rpm}
hostname=`hostname`
GUEST_IMG=${GUEST_IMG:-"7.6"}
guest_dpdk=${guest_dpdk:-dpdkrpms/1711}
GUEST_DPDK_VERSION=${GUEST_DPDK_VERSION:-1711}
Trex_nic1=${Trex_nic1:-Dell02_p3p1}
Trex_nic2=${Trex_nic2:-Dell02_p3p2}
NetScout_nic1=${NetScout_nic1:-Dell15_p5p1}
NetScout_nic2=${NetScout_nic2:-Dell15_p5p2}
NetScout_speed=${NetScout_speed:-10}
xena_module=${xena_module:-9}
image_method=${image_method:-download}
QCOW_LOC=${QCOW_LOC:-China}
QEMU_VER=${QEMU_VER:-212}
NIC_DRIVER=${NIC_DRIVER:-"ixgbe"}
selinux_policy_rpm=${selinux_policy_rpm:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/openvswitch-selinux-extra-policy/1.0/7.el8fdp/noarch/openvswitch-selinux-extra-policy-1.0-7.el8fdp.noarch.rpm"}
guest_mode=${guest_mode:-"viommu"}
function random_mac() {
    echo -n 00:60:2F; dd bs=1 count=3 if=/dev/random 2>/dev/null | hexdump -v -e '/1 ":%02X"'
}
vf0_mac=$(random_mac)
vf1_mac=$(random_mac)
test_type=${test_type:-"tunnel1_test"}
. /etc/os-release
OS_NAME="$VERSION_ID"
set -x
if [ ${QCOW_LOC} == "China" ];then
	WEB_SERVER="http://netqe-bj.usersys.redhat.com/share/tli/vsperf_img"
else
	WEB_SERVER="http://netqe-infra01.knqe.lab.eng.bos.redhat.com/vm"
fi
case "$(hostname)" in
	"dell-per730-50.rhts.eng.pek2.redhat.com" )
                NIC1_NAME=${NIC1_NAME:-p6p1}
                NIC2_NAME=${NIC2_NAME:-p6p2}
                NUMA=${NUMA:-0}
                ISOLCPUS=${ISOLCPUS_SERVER:-2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62,64,66,68,70}
        ;;
	"dell-per730-15.rhts.eng.pek2.redhat.com" )
                NIC1_NAME=${NIC1_NAME:-p5p1}
                NIC2_NAME=${NIC2_NAME:-p5p2}
                NUMA=${NUMA:-0}
                ISOLCPUS=${ISOLCPUS_SERVER:-2,4,6,8,10,12,14,16,18,20,22,24,26,28,30}
        ;;
	"dell-per730-02.rhts.eng.pek2.redhat.com" )
                NIC1_NAME=${NIC1_NAME:-p3p1}
                NIC2_NAME=${NIC2_NAME:-p3p2}
                NUMA=${NUMA:-1}
                ISOLCPUS=${ISOLCPUS_SERVER:-1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31}
        ;;
	"dell-per730-01.rhts.eng.pek2.redhat.com" )
                NIC1_NAME=${NIC1_NAME:-p3p1}
                NIC2_NAME=${NIC2_NAME:-p3p2}
                NUMA=${NUMA:-1}
                ISOLCPUS=${ISOLCPUS_SERVER:-1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31}
        ;;
        "netqe22.knqe.lab.eng.bos.redhat.com" )
                NUMA=${NUMA:-0}
                NIC1_NAME=${NIC1_NAME:-p7p1}
                NIC2_NAME=${NIC2_NAME:-p7p2}
                ISOLCPUS=${ISOLCPUS:-2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46}
        ;;
        "dell-per730-52.rhts.eng.pek2.redhat.com" )
                NUMA=${NUMA:-0}
                NIC1_NAME=${NIC1_NAME:-p6p1}
		NIC2_NAME=${NIC2_NAME:-p6p2}
                ISOLCPUS=${ISOLCPUS:-2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54}
        ;;
	"cisco-c220m4-01.rhts.eng.pek2.redhat.com" )
                NIC1_NAME=${NIC1_NAME:-enp9s0}
                NIC2_NAME=${NIC2_NAME:-enp10s0}
                NUMA=${NUMA:-0}
                ISOLCPUS=${ISOLCPUS_SERVER:-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29}
        ;;
        "netqe15.knqe.lab.eng.bos.redhat.com" )
                NUMA=${NUMA:-1}
                NIC1_NAME=${NIC1_NAME:-p5p1}
                NIC2_NAME=${NIC2_NAME:-p5p2}
                ISOLCPUS=${ISOLCPUS:-2,4,6,8,10,12,14}
        ;;
esac
VCPUS=${VCPUS:-3}
PMD_CPU_MASK=$(/usr/bin/python2 ${CASE_PATH}/get_pmd.py --cmd host_pmd --nic "${NIC1_NAME}" --pmd 4)
if [ $VERSION_ID == "8.0" ];then
	python_cmd="/usr/libexec/platform-python"
else
	python_cmd="python"
fi


install_qemu() {

if [ "$QCOW_LOC" == "China" ]
    then
    SERVER="download.eng.pnq.redhat.com"
elif [ "$QCOW_LOC" == "Westford" ]
    then
    SERVER="download-node-02.eng.bos.redhat.com"
fi

. /etc/os-release
OS_NAME="$VERSION_ID"
if [ $OS_NAME != "8.0" ];then
if [ "$QEMU_VER" == "OSP8" ]
        then
        yum install -y qemu-kvm-rhev* >> ${CASE_PATH}/qemu_install.log

elif [ "$QEMU_VER" == "29" ]
    then
    mkdir ~/qemu29
    wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.9.0/16.el7_4.13/x86_64/qemu-img-rhev-2.9.0-16.el7_4.13.x86_64.rpm -P ~/qemu29
    wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.9.0/16.el7_4.13/x86_64/qemu-kvm-common-rhev-2.9.0-16.el7_4.13.x86_64.rpm -P ~/qemu29
    wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.9.0/16.el7_4.13/x86_64/qemu-kvm-rhev-2.9.0-16.el7_4.13.x86_64.rpm -P ~/qemu29
    wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.9.0/16.el7_4.13/x86_64/qemu-kvm-tools-rhev-2.9.0-16.el7_4.13.x86_64.rpm -P ~/qemu29
    rpm -e qemu-kvm-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
    rpm -e qemu-kvm-common-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
    rpm -e qemu-img-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
    rpm -e qemu-kvm-tools-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
    yum install -y http://download-node-02.eng.bos.redhat.com/brewroot/packages/seabios/1.10.2/3.el7_4.1/noarch/seabios-bin-1.10.2-3.el7_4.1.noarch.rpm
    yum install -y http://download-node-02.eng.bos.redhat.com/brewroot/packages/seabios/1.10.2/3.el7_4.1/noarch/seavgabios-bin-1.10.2-3.el7_4.1.noarch.rpm
    yum install -y http://download-node-02.eng.bos.redhat.com/brewroot/packages/ipxe/20170123/1.git4e85b27.el7_4.1/noarch/ipxe-roms-qemu-20170123-1.git4e85b27.el7_4.1.noarch.rpm
    yum install -y ~/qemu29/qemu-img-rhev-2.9.0-16.el7_4.13.x86_64.rpm >> ${CASE_PATH}/qemu_install.log
    yum install -y ~/qemu29/qemu-kvm-rhev-2.9.0-16.el7_4.13.x86_64.rpm >> ${CASE_PATH}/qemu_install.log
    yum install -y ~/qemu29/qemu-kvm-common-rhev-2.9.0-16.el7_4.13.x86_64.rpm >> ${CASE_PATH}/qemu_install.log
    yum install -y ~/qemu29/qemu-kvm-tools-rhev-2.9.0-16.el7_4.13.x86_64.rpm >> ${CASE_PATH}/qemu_install.log
    yum install -y ~/qemu29/qemu-kvm-rhev-2.9.0-16.el7_4.13.x86_64.rpm >> ${CASE_PATH}/qemu_install.log
elif [ "$QEMU_VER" == "210" ]
    then
        mkdir ~/qemu210
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.10.0/20.el7/x86_64/qemu-img-rhev-2.10.0-20.el7.x86_64.rpm -P ~/qemu210/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.10.0/20.el7/x86_64/qemu-kvm-common-rhev-2.10.0-20.el7.x86_64.rpm -P ~/qemu210/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.10.0/20.el7/x86_64/qemu-kvm-rhev-2.10.0-20.el7.x86_64.rpm -P ~/qemu210/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.10.0/20.el7/x86_64/qemu-kvm-rhev-debuginfo-2.10.0-20.el7.x86_64.rpm -P ~/qemu210/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.10.0/20.el7/x86_64/qemu-kvm-tools-rhev-2.10.0-20.el7.x86_64.rpm -P ~/qemu210/.
        rpm -e qemu-kvm-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-kvm-common-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-img-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-kvm-tools-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        pushd ~/qemu210
        yum install * -y
        popd
elif [ "$QEMU_VER" == "212" ]
    then
        mkdir ~/qemu212
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.12.0/13.el7/x86_64/qemu-img-rhev-2.12.0-13.el7.x86_64.rpm -P ~/qemu212/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.12.0/13.el7/x86_64/qemu-kvm-common-rhev-2.12.0-13.el7.x86_64.rpm -P ~/qemu212/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.12.0/13.el7/x86_64/qemu-kvm-rhev-2.12.0-13.el7.x86_64.rpm -P ~/qemu212/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.12.0/13.el7/x86_64/qemu-kvm-rhev-debuginfo-2.12.0-13.el7.x86_64.rpm -P ~/qemu212/.
        wget http://$SERVER/brewroot/packages/qemu-kvm-rhev/2.12.0/13.el7/x86_64/qemu-kvm-tools-rhev-2.12.0-13.el7.x86_64.rpm -P ~/qemu212/.
        rpm -e qemu-kvm-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-kvm-common-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-img-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        rpm -e qemu-kvm-tools-rhev-2.6.0-28.el7_3.9.x86_64 --nodeps >> ${CASE_PATH}/qemu_install.log
        pushd ~/qemu212
        yum install * -y
        popd
fi
else
dnf module install virt -y
fi

}

install_rpms(){
        #install qemu packages
        install_qemu
	#install libvirt
        yum install -y libvirt virt-install virt-manager virt-viewer
        #install python
	if [ "$VERSION_ID" == "8.0" ];then
        	yum install -y python2
	else
		yum install -y python
	fi
}

install_ovs(){
	container_selinux_policy_rpm=${container_selinux_policy_rpm:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/container-selinux/2.77/1.el7_6/noarch/container-selinux-2.77-1.el7_6.noarch.rpm"}
	yum install -y policycoreutils-python
        yum install -y ${container_selinux_policy_rpm}
        yum install -y ${selinux_policy_rpm}
        yum install -y ${OVS_URL}
}


install_dpdk(){
	rpm -ivh ${DPDK_URL}
        rpm -ivh ${DPDK_TOOL_URL}
}

install_python34() {
	pushd /root 1>/dev/null
	wget https://www.python.org/ftp/python/3.4.3/Python-3.4.3.tgz > /dev/null 2>&1
	tar zxvf Python-3.4.3.tgz > /dev/null 2>&1
	pushd /root/Python-3.4.3
        ./configure > /dev/null 2>&1
	make > /dev/null 2>&1
	make install > /dev/null 2>&1
	popd 1>/dev/null
}

config_connection() {
install_python34
pushd /root/ 1>/dev/null
git clone https://github.com/ctrautma/NetScout.git
pushd /root/NetScout 1>/dev/null
#cp ${CASE_PATH}/settings.cfg .
chmod 777 NSConnect.py
if [ "$NetScout_speed" == "10" ];then
if [ "$QCOW_LOC" == "China" ];then
cat >> /root/NetScout/settings.cfg <<  EOF
[INFO]
password = bmV0c2NvdXQx
username = YWRtaW5pc3RyYXRvcg==
port = NTMwNTg=
host = MTAuNzMuODguOQ==
EOF
else
cat >> /root/NetScout/settings.cfg <<  EOF
[INFO]
password = bmV0c2NvdXQx
username = YWRtaW5pc3RyYXRvcg==
port = NTMwNTg=
host = MTAuMTkuMTUuNjU=
EOF
fi
elif [ "$NetScout_speed" == "100" ];then
if [ "$QCOW_LOC" == "China" ];then
cat >> /root/NetScout/settings.cfg <<  EOF
[INFO]
password = bmV0c2NvdXQx
username = YWRtaW5pc3RyYXRvcg==
port = NTMwNTg=
host = MTAuNzMuODguOA==
EOF
else
cat >> /root/NetScout/settings.cfg <<  EOF
[INFO]
password = bmV0c2NvdXQx
username = YWRtaW5pc3RyYXRvcg==
port = NTMwNTg=
host = MTAuMTkuMTUuMTAy
EOF
fi
fi
/root/Python-3.4.3/python NSConnect.py --connect ${Trex_nic1} ${NetScout_nic1}
/root/Python-3.4.3/python NSConnect.py --connect ${Trex_nic2} ${NetScout_nic2}

popd 1>/dev/null

}



Config_Hugepage() {
	#config the hugepage
	if [ $VERSION_ID == "7.4" ] || [ $VERSION_ID == "7.3" ]
	then
		rpm -Uvh http://download-node-02.eng.bos.redhat.com/brewroot/packages/tuned/2.8.0/3.el7/noarch/tuned-2.8.0-3.el7.noarch.rpm --nodeps
        	rpm -ivh http://download-node-02.eng.bos.redhat.com/brewroot/packages/tuned/2.8.0/3.el7/noarch/tuned-profiles-realtime-2.8.0-3.el7.noarch.rpm --nodeps
        	rpm -ivh http://download-node-02.eng.bos.redhat.com/brewroot/packages/tuned/2.8.0/3.el7/noarch/tuned-profiles-nfv-2.8.0-3.el7.noarch.rpm --nodeps
        	rpm -ivh http://download-node-02.eng.bos.redhat.com/brewroot/packages/tuned/2.8.0/3.el7/noarch/tuned-profiles-cpu-partitioning-2.8.0-3.el7.noarch.rpm --nodeps
	else
    		yum install -y tuned-profiles-cpu-partitioning
	fi

	echo -e "isolated_cores=$ISOLCPUS" >> /etc/tuned/cpu-partitioning-variables.conf
        tuned-adm profile cpu-partitioning	
	if [ $VERSION_ID != "8.0" ];then
		sed -i 's/\(GRUB_CMDLINE_LINUX.*\)"$/\1/g' /etc/default/grub
        	if [ ${NIC_DRIVER} == "qede" ];then
                	sed -i "s/GRUB_CMDLINE_LINUX.*/& nohz=on default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr \"/g" /etc/default/grub
        	else
                	sed -i "s/GRUB_CMDLINE_LINUX.*/& nohz=on default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt \"/g" /etc/default/grub
        	fi
		grub2-mkconfig -o /boot/grub2/grub.cfg
	else
		kernelopts=$(grub2-editenv - list | grep kernelopts | sed -e 's/kernelopts=//g')
		if [ ${NIC_DRIVER} == "qede" ];then
			grub2-editenv - set kernelopts="$kernelopts isolcpus='"$ISOLCPUS"' intel_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=24 modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr"
		else
			grub2-editenv - set kernelopts="$kernelopts isolcpus='"$ISOLCPUS"' intel_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=24"
		fi
	cat /boot/grub2/grubenv
	fi
        if [ ${NIC_DRIVER} == "mlx4_en" ];then
                mlx4_patch
        fi
	rhts-reboot
	cat /proc/cmdline
}

download_image(){
	wget -P /var/lib/libvirt/images/ ${WEB_SERVER}/rhel${GUEST_IMG}-vsperf-1Q-viommu.qcow2
	cp /var/lib/libvirt/images/rhel${GUEST_IMG}-vsperf-1Q-viommu.qcow2 /var/lib/libvirt/images/master1.qcow2
	cp /var/lib/libvirt/images/rhel${GUEST_IMG}-vsperf-1Q-viommu.qcow2 /var/lib/libvirt/images/master2.qcow2
	echo NIC1="'${NIC1_NAME}'" >> ${CASE_PATH}/nic_info.py
        echo GUEST_IMG="'${GUEST_IMG}'" >> ${CASE_PATH}/nic_info.py
        echo VCPUS="'${VCPUS}'" >> ${CASE_PATH}/nic_info.py
        echo NUMA="'${NUMA}'" >> ${CASE_PATH}/nic_info.py
	python2 ${CASE_PATH}/change_xml.py
}

create_vf(){
	sriov_create_vfs $NIC1_NAME 0 2
	ip link set $NIC1_NAME vf 0 mac ${vf0_mac}
	ip link set $NIC1_NAME vf 1 mac ${vf1_mac}
}

build_vf0_topo(){
	start_guest1
	sleep 30
	sriov_attach_vf_to_vm $NIC1_NAME 0 $1 master1 $2
}

build_vf1_topo(){
	vf1_bus_info=$(sriov_get_vf_bus_info $NIC1_NAME 0 2)
        modprobe vfio-pci
	/usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci ${vf1_bus_info}
	systemctl restart openvswitch
	ovs-vsctl set Open_vSwitch . other_config={}
        ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
        ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="1024,1024"
	ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=$1
	ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
	ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev
	ovs-vsctl add-port ovsbr0 dpdk0 -- set Interface dpdk0 type=dpdk type=dpdk options:dpdk-devargs=${vf1_bus_info}
	ovs-vsctl add-port ovsbr0 dpdkvhostuserclient0 -- set Interface dpdkvhostuserclient0 type=dpdkvhostuserclient -- set Interface dpdkvhostuserclient0 options:vhost-server-path=/tmp/dpdkvhostuserclient0
}


build_tunnel2_topo(){
        vf1_bus_info=$(sriov_get_vf_bus_info $NIC1_NAME 0 2)
        modprobe vfio-pci
        /usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci ${vf1_bus_info}
        systemctl restart openvswitch
        ovs-vsctl set Open_vSwitch . other_config={}
        ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
        ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="1024,1024"
        ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=$1
        ovs-vsctl --no-wait set Open_vSwitch . other_config:vhost-iommu-support=true
        ovs-vsctl add-br ovsbr0 -- set bridge ovsbr0 datapath_type=netdev
        ovs-vsctl add-br ovsbr1 -- set bridge ovsbr1 datapath_type=netdev
        ovs-vsctl add-port ovsbr1 dpdk0 -- set Interface dpdk0 type=dpdk type=dpdk options:dpdk-devargs=${vf1_bus_info}
        ovs-vsctl add-port ovsbr0 dpdkvhostuserclient0 -- set Interface dpdkvhostuserclient0 type=dpdkvhostuserclient -- set Interface dpdkvhostuserclient0 options:vhost-server-path=/tmp/dpdkvhostuserclient0
	ovs-vsctl add-port ovsbr0 vxlan0 -- set interface vxlan0 type=vxlan options:remote_ip=${remote_veth} options:dst_port=4789 options:key=42
	ip addr add ${local_veth}/24 dev ovsbr1
	ip link set ovsbr0 up
	ip link set ovsbr1 up
}


start_guest1(){
	echo -e "group = 'hugetlbfs'" >> /etc/libvirt/qemu.conf
        systemctl restart libvirtd
	virsh define ${CASE_PATH}/guest1.xml
	chmod 777 /var/lib/libvirt/images/
	virsh start master1
}

tunnel1_guest_config(){
	vmsh run_cmd master1 "ip link set enp3s0 up"
	vmsh run_cmd master1 "ip addr add ${local_veth}/24 dev enp3s0"
	vmsh run_cmd master1 "ip link add vxlan0 type vxlan id 42 remote ${remote_veth} local ${local_veth} dev enp3s0"		
	vmsh run_cmd master1 "ip addr add ${local_addr}/24 dev vxlan0"
	vmsh run_cmd master1 "ip link set vxlan0 up"
	vmsh run_cmd master1 "systemctl stop firewalld"
}

tunnel2_guest_config(){
	systemctl restart openvswitch
        vmsh run_cmd master2 "ip link set eth0 up"
        vmsh run_cmd master2 "ip addr add ${local_addr}/24 dev eth0"
        vmsh run_cmd master2 "systemctl stop firewalld"
}

tunnel1_ping_test(){
	vmsh run_cmd master1 "ping $remote_addr -c 5"
}

tunnel2_ping_test(){
	#change the mac address different each other
	vmsh run_cmd master2 "ifconfig eth0 hw ether 52:54:00:11:8f:e8"
        vmsh run_cmd master2 "ping $remote_addr -c 10"
}

guest1_testpmd(){
	local cmd=(
                        {rpm -ivh /root/${guest_dpdk}/dpdk*.rpm}
                        {/root/one_gig_hugepages.sh 1}
			{rmmod vfio_pci}
			{rmmod vfio_iommu_type1}
			{rmmod vfio}
			{modprobe vfio enable_unsafe_noiommu_mode=Y}
			{modprobe vfio-pci}
			{/usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:02:00.0}
                )
        vmsh cmd_set master1 "${cmd[*]}"
        VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd master1 "/usr/bin/testpmd -l 0,1,2 -n4 --socket-mem 1024 --legacy-mem -- --burst=64 -i --rxd=512 --txd=512 --nb-cores=2 --rxq=1 --txq=1 --disable-rss --forward-mode=macswap --auto-start"
}

start_guest2(){
        echo -e "group = 'hugetlbfs'" >> /etc/libvirt/qemu.conf
        systemctl restart libvirtd
        virsh define ${CASE_PATH}/guest2.xml
        chmod 777 /var/lib/libvirt/images/
        virsh start master2
}

guest2_testpmd(){
        local cmd=(
                        {rpm -ivh /root/${guest_dpdk}/dpdk*.rpm}
                        {/root/one_gig_hugepages.sh 1}
                        {modprobe vfio-pci}
                        {/usr/share/dpdk/usertools/dpdk-devbind.py -b vfio-pci 0000:04:00.0}
                )
        vmsh cmd_set master2 "${cmd[*]}"
        VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd master2 "/usr/bin/testpmd -l 0,1,2 -n4 --socket-mem 1024 --legacy-mem -- --burst=64 -i --rxd=512 --txd=512 --nb-cores=2 --rxq=1 --txq=1 --disable-rss --forward-mode=macswap --auto-start"
}

install_trex(){
        wget -P /tmp/ http://trex-tgn.cisco.com/trex/release/v2.36.tar.gz
        pushd /tmp/
        tar xzvf v2.36.tar.gz
        popd
	cat > /etc/trex_cfg.yaml<<-EOF
                - port_limit      : 2
                  version         : 2
                  interfaces    : ["$PCI_NIC0","$PCI_NIC1"]
                  port_info       :  # Port IPs. Change to suit your needs. In case of loopback, you can leave as is.
                      - dest_mac        :   [0x00,0x00,0x00,0x00,0x00,0x02]  # port 0
                        src_mac         :   [0x00,0x00,0x00,0x00,0x00,0x01]
                      - dest_mac        :   [0x00,0x00,0x00,0x00,0x00,0x01]  # port 1
                        src_mac         :   [0x00,0x00,0x00,0x00,0x00,0x02]
	EOF
        set -x
        pushd /tmp/v2.36/
        . /etc/os-release
        if [ "$VERSION_ID" != "8.0" ];then
                nohup ./t-rex-64 -i -c 10 &
        else
                PYTHON=/usr/libexec/platform-python nohup ./t-rex-64 -i -c 10 --no-scapy-server &
        fi
        echo "check trex process after start trex"
        ps aux|grep t-rex
        popd
        echo "check trex process again"
        ps aux|grep t-rex
        echo "install trex finish"
        set +x  
}


vf0_vf1_bifurcated_test(){
	ethtool -N ${NIC1_NAME} flow-type udp4 src-ip 10.0.100.2 dst-ip 10.0.100.1 vf 0
	ethtool -N ${NIC1_NAME} flow-type udp4 src-ip 10.0.100.1 dst-ip 10.0.100.2 vf 1
}

send_traffic(){
	python2 ${CASE_PATH}/send.py --pkt_size=64 -c 127.0.0.1 -s $1 -d $2 --speed=5000000
}

send_traffic2(){
        python2 ${CASE_PATH}/send2.py --pkt_size=64 -c 127.0.0.1 -s1 $1 -d1 $2 -s2 $3 -d2 $4 --speed=5000000
}

mlx4_patch()
{
        yum install -y libibverbs
        echo options mlx4_core log_num_mgm_entry_size=-1  >> /etc/modprobe.d/mlx4.conf
        dracut -f -v
}

clear_env()
{
	virsh destroy master1
	virsh undefine master1
	virsh destroy master2
	virsh undefine master2
	sriov_create_vfs $NIC1_NAME 0 0
	ovs-vsctl del-br ovsbr0
}

#-------------------------------------------------------------------------------------------
#
#                               Host A (DUT)                                                 
# +---------------------------------------------------------------------------+            
# |                                                                           |       
# |                                                                           |       
# |  +--------------------------+  +--------------------------+               |       
# |  |           vm1            |  |           vm2            |               |
# |  |       (bind to dpdk)     |  |     (vhostuser port)     |               |       
# |  +--+---+---+---+-.-+---+---+  +--+---+--+--.-+---+---+---+               |                                  
# |                   .                         .                             |       
# |                   .                         .                             | 
# |                   .                     +---.---+                         |
# |                   .                     |  ovs  |                         |
# |                   .                     |       |                         |
# |                   .                     +---.---+                         |
# |                   .                         .                             |
# |                   .                         .                             |
# |               +---.---+          +----------.---+                         |
# |               |  VF1  |----------|  VF2         |                         |
# |               +-------+          |(bind to dpdk)|                         |
# |               |                  +--------------+                         |                  
# +---------------|   PF PORT(bifurcated driver)    |-------------------------+
#                 +------------------.--------------+                            
#                                    .   
#                                    . 
#                                    .
#                               +---.-----+ 
# +-----------------------------| PF PORT |-----------------------------------+
# |                             +---------+                                   |
# |                                                                           |
# |                              TREX                                         |
# |                                                                           |
# +-------------------------------------------------------------+-------------+
#
#                               Host B (TREX)
#----------------------------------------------------------------------------------------------------------------

#-------------------------------------Tunnel TOPO1(VF passthough to VM, using VF as VTEP)------------------------
#   +------------+-------------+
#   |        Server 1          |
#   | +----+----+              |
#   | | VXLAN0  |              |
#   | | VNI 34  |              |
#   | | 20.0.0.1|              |
#   | +---------+              |
#   |                          |
#   |        30.0.0.1          |
#   |        VTEP (VF)         |
#   +--------------------------+
#               PF|
#                 |
#                 |
#                 |   +-------------+
#                 |   |   Layer 3   |
#                 |---|   Network   |
#                     |             |
#                     +-------------+
#                 |
#                 |
#                +----------------+               
#                |
#                |PF
#   +------------+-------------+
#   |        VTEP (VF)         |
#   |        30.0.0.2          |
#   |                          |
#   | +----+----+              |
#   | | VXLAN0  |              |
#   | | VNI 34  |              |
#   | | 20.0.0.2|              |
#   | +---------+              |
#   |        Server 2          |
#   +--------------------------+
#----------------------------------------------------------------------------------------------------------------

#-------------------------------------Tunnel TOPO2(VF add to ovs bridge, using VF as VTEP)------------------------                                                                                
# +---------------------------------------------------------------------------+            
# |                               Server1                                     |       
# |                                                                           |       
# |                     +--------------------------+                          |       
# |                     |           vm             |                          |
# |                     |     (vhostuser port)     |                          |       
# |                     +--+---+--+--.-+---+---+---+                          |                                  
# |                                  .                                        |       
# |                                  .                                        | 
# |                              +---.---+                                    |
# |                              |  ovs  |                                    |
# |                              +---.---+                                    |
# |                                  . vxlan0                                 |
# |                                  .                                        |
# |                         +--------.-----+                                  |
# |                         |  VETH VF     |                                  |
# |                         |(bind to dpdk)|                                  |
# |                         +--------------+                                  |                  
# +---------------------------------PF----------------------------------------+
#                                    .                            
#                                    .   
#                                    . 
#                                    .
# +---------------------------------PF----------------------------------------+            
# |                         +--------------+                                  |
# |                         |  VETH VF     |                                  |
# |                         |(bind to dpdk)|                                  |
# |                         +--------------+                                  | 
# |                                  .                                        | 
# |                                  .                                        |
# |                                  . vxlan0                                 |       
# |                              +---.---+                                    |
# |                              |  ovs  |                                    |
# |                              +---.---+                                    |      
# |                                  .                                        |
# |                                  .                                        |                                                                     |       
# |                     +--------------------------+                          |       
# |                     |           vm             |                          |
# |                     |     (vhostuser port)     |                          |       
# |                     +--+---+--+--.-+---+---+---+                          |                                  
# |                                                                           |       
# |                               Server2                                     |  
# +---------------------------------------------------------------------------+
#
#----------------------------------------------------------------------------------------------------------------


#-----------nic partition testing-------

#main test
rlJournalStart
rlPhaseStartSetup
if ! ls ${CASE_PATH}/TASK*; then
        rlRun "install_rpms"
        rlRun "Config_Hugepage"
	touch ${CASE_PATH}/TASK1
        ls -l ${CASE_PATH}
        rhts-reboot
fi
rlPhaseEnd

rlPhaseStartTest "start test"
if [ -f ${CASE_PATH}/TASK1 ]; then
	rlRun "install_rpms"
        rlRun "install_ovs"
        rlRun "install_dpdk"
        rlRun "download_image"
        rlRun "config_connection"
	if i_am_server;then
		local_veth="30.0.0.1"
		remote_veth="30.0.0.2"
		local_addr="20.0.0.1"
		remote_addr="20.0.0.2"
		if [ ${test_type} == "tunnel1_test" ];then
                rlPhaseStartTest "Start tunnel1 test(vf passthough to vm)"
			rlRun "create_vf"
			rlRun "build_vf0_topo 1 ${vf0_mac}"
			rlRun "tunnel1_guest_config"
			sync_set client tunnel1_env_ready
                rlPhaseEnd
                elif [ ${test_type} == "tunnel2_test" ];then
                rlPhaseStartTest "Start tunnel2 test(add vf to ovs bridge)"
                        rlRun "create_vf"
                        rlRun "build_tunnel2_topo ${PMD_CPU_MASK}"
                        rlRun "start_guest2"
                        rlRun "tunnel2_guest_config"
                        sync_set client tunnel2_env_ready
                rlPhaseEnd
		elif [ ${test_type} == "performance_test" ];then
		rlPhaseStartTest "Start performance test"
			rlRun "create_vf"
			rlRun "build_vf0_topo 1 ${vf0_mac}"
			rlRun "guest1_testpmd"
        		rlRun "build_vf1_topo ${PMD_CPU_MASK}"
			rlRun "start_guest2"
			rlRun "guest2_testpmd"
			sync_set client env_ready
		rlPhaseEnd
		fi
		#rlRun "vf0_basic_test"
		#rlRun "vf1_basic_test"
		#rlRun "vf0_vf1_test"
		#rlRun "vf0_vf1_bifurcated_test"
		#rlRun "vf0_vlan_test"
		#rlRun "vf1_vlan_test"
	elif i_am_client; then
		local_veth="30.0.0.2"
                remote_veth="30.0.0.1"
                local_addr="20.0.0.2"
                remote_addr="20.0.0.1"
		nic1_mac=`ip link show ${NIC1_NAME} | grep ether | awk '{print $2}'`
                if [ ${test_type} == "tunnel1_test" ];then
                rlPhaseStartTest "Start tunnel1 test(vf passthough to vm)"
                        rlRun "create_vf"
                        rlRun "build_vf0_topo 2 ${vf1_mac}"
                        rlRun "tunnel1_guest_config"
			sync_wait server tunnel1_env_ready
			rlRun "tunnel1_ping_test"
                rlPhaseEnd
		elif [ ${test_type} == "tunnel2_test" ];then
                rlPhaseStartTest "Start tunnel2 test(add vf to ovs bridge)"
                        rlRun "create_vf"
			rlRun "build_tunnel2_topo ${PMD_CPU_MASK}"
                        rlRun "start_guest2"
                        rlRun "tunnel2_guest_config"
                        sync_wait server tunnel2_env_ready
                        rlRun "tunnel2_ping_test"
                rlPhaseEnd
                elif [ ${test_type} == "performance_test" ];then
                rlPhaseStartTest "Start performance test"
                	rlRun "create_vf"	
			rlRun "install_trex"
			sync_wait server env_ready
			rlRun "send_traffic ${nic1_mac} ${vf0_mac}"
			rlRun "send_traffic ${nic1_mac} ${vf1_mac}"
                rlPhaseEnd
		fi
	fi
fi


rlJournalPrintText
rlJournalEnd
