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

CASE_PATH=$(dirname $(readlink -f $0))

test -f `pwd`/Perf-Verify.conf || exit 1 

set -o allexport
source Perf-Verify.conf
set +o allexport

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

source lib/lib_nc_sync.sh || exit 1
source lib/lib_utils.sh || exit 1
source /usr/share/beakerlib/beakerlib.sh || exit 1

add_epel_repo()
{
	if (( $SYSTEM_VERSION_ID < 80 ))
	then
		yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	else
		dnf -y install epel-release
	fi

}

install_package()
{
	add_epel_repo
	if (( $SYSTEM_VERSION_ID < 80 ))
	then
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
	local cpu_array=($cpus)
	pmd_mask=`python tools.py get-pmd-masks "${cpu_array[@]}"`
	echo $pmd_mask
}

get_isolate_cpus()
{
	local nic_name=$1
	local isolate_cpus=$(python tools.py get-isolate-cpus-with-nic $nic_name)
	echo $isolate_cpus
}

config_isolated_cpu_and_Gb_hugepage()
{
	rpm -q grubby || yum -y install grubby
	rpm -qa | grep tuned-profiles-cpu-partitioning || yum -y install tuned-profiles-cpu-partitioning

	local cpus=$1
	local hpage_num=$2

	echo -e "isolated_cores=${cpus}" >> /etc/tuned/cpu-partitioning-variables.conf
	tuned-adm profile cpu-partitioning
	
	local hpage_cmd_line="nohz=on \
	default_hugepagesz=1G hugepagesz=1G \
	hugepages=${hpage_num} intel_iommu=on iommu=pt \
	modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr"

	local default_kernel=$(grubby --default-kernel)

	grubby --args="${hpage_cmd_line}" --update-kernel ${default_kernel}

	#here make a mark file for reboot check , please do not remove it 
	touch /tmp/nic_cert_file 

	reboot

	cat /proc/cmdline
}

usage () 
{
   cat <<EOF
	Usage: $progname [-t test to execute] [-h print help]
	-t tests to execute ['1Q, 2Q, Jumbo, Kernel, pvp_cont','SRIOV'] default is to run all tests
	-h print this help message
EOF
   exit 0
}


#######################
# main
rlJournalStart
rlPhaseStartSetup
if [[ ! -f /tmp/nic_cert_file ]]
then
	rlRun install_init_package
	rlRun install_package
	rlRun init_python_env
	cpus_for_isolate=`get_isolate_cpus $NIC1`
	rlRun "config_isolated_cpu_and_Gb_hugepage ${cpus_for_isolate} 24 "
fi
rlPhaseEnd

rlPhaseStartTest "START NIC CERTIFICATION ALL TEST"
if [[ -f /tmp/sriov_dpdk_pft ]]
then
	rlRun "cat /proc/cmdline"
	rlRun init_python_env
	. Perf-Verify.sh "${@}"

fi
rlPhaseEnd

rlJournalPrintText
rlJournalEnd



