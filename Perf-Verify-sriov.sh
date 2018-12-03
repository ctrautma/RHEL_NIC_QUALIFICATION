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

. ./Perf-Verify.sh --source-only

echo "*** SR-IOV MUST be enabled already for this test to work!!!! ***"

append_log() {

if test -f /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
then
    source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
else
    time_stamp=$(date +%Y-%m-%d-%T)
    NIC_LOG_FOLDER="/root/RHEL_NIC_QUAL_LOGS/$time_stamp"
    mkdir $NIC_LOG_FOLDER || fail "log folder creation" "Cannot create time stamp folder for logs in root home folder"
    echo "NIC_LOG_FOLDER=$NIC_LOG_FOLDER" > /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
fi
    echo "*** Placing all output logs to $NIC_LOG_FOLDER"
}
generate_sriov_conf() {

    NIC1_VF_PCI_ADDR=`ethtool -i $NIC1_VF | awk /bus-info/ | awk {'print $2'}`
    NIC2_VF_PCI_ADDR=`ethtool -i $NIC2_VF | awk /bus-info/ | awk {'print $2'}`
    NIC1_VF_MAC=`cat /sys/class/net/$NIC1_VF/address`
    NIC2_VF_MAC=`cat /sys/class/net/$NIC2_VF/address`


cat <<EOT >>/root/vswitchperf/sriov.conf

TRAFFIC = {
    'traffic_type' : 'rfc2544_throughput',
    'frame_rate' : 100,
    'bidir' : 'True',  # will be passed as string in title format to tgen
    'multistream' : 1024,
    'stream_type' : 'L3',
    'pre_installed_flows' : 'No',           # used by vswitch implementation
    'flow_type' : 'port',                   # used by vswitch implementation

    'l2': {
        'framesize': 64,
        'srcmac': '$NIC1_VF_MAC',
        'dstmac': '$NIC2_VF_MAC',
    },
    'l3': {
        'enabled': True,
        'proto': 'udp',
        'srcip': '1.1.1.1',
        'dstip': '90.90.90.90',
    },
    'l4': {
        'enabled': True,
        'srcport': 3000,
        'dstport': 3001,
    },
    'vlan': {
        'enabled': False,
        'id': 0,
        'priority': 0,
        'cfi': 0,
    },
    'capture': {
        'enabled': False,
        'tx_ports' : [0],
        'rx_ports' : [1],
        'count': 1,
        'filter': '',
    },
}
WHITELIST_NICS = ['$NIC1_VF_PCI_ADDR', '$NIC2_VF_PCI_ADDR']

PIDSTAT_MONITOR = ['ovs-vswitchd', 'ovsdb-server', 'qemu-system-x86_64', 'vpp', 'testpmd', 'qemu-kvm']
TRAFFICGEN_TREX_PROMISCUOUS=True

GUEST_TESTPMD_PARAMS = ['-l 0,1,2 -n 4 --socket-mem 512 -- '
                        '--burst=64 -i --txqflags=0xf00 '
                        '--disable-hw-vlan --nb-cores=2, --txq=1 --rxq=1 --rxd=$SRIOV_RXD_SIZE --txd=$SRIOV_TXD_SIZE']

EOT

}

run_sriov_tests() {
    echo ""
    echo "************************************************"
    echo "*** Running 64/1500 Bytes SR-IOV VSPerf TEST ***"
    echo "************************************************"
    echo ""

cd /root/vswitchperf
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python3 ./vsperf pvp_tput --conf-file=/root/vswitchperf/sriov.conf --vswitch=none --vnf=QemuPciPassthrough &> $NIC_LOG_FOLDER/vsperf_pvp_sriov.log &

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid
}

print_results_sr_iov() {
if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_sriov*' -print -quit)"
then
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_sr_iov_results.txt
#################################################
#      RESULTS OF SRIOV VSPERF TESTS            #
#                                               #
EOT
fi

if test -n "$(find $NIC_LOG_FOLDER -maxdepth 1 -name 'vsperf_pvp_sriov.log' -print -quit)"
then
mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_sriov.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte SR_IOV PVP test result: ${array[0]} #
# 1500 Byte SR_IOV PVP test result: ${array[1]} #
EOT
fi

cat <<EOT >>$NIC_LOG_FOLDER/vsperf_sr_iov_results.txt
##################################################
EOT
cat $NIC_LOG_FOLDER//vsperf_sr_iov_results.txt

}


sriov_check() {

    echo "*** Checking Config File for SR-IOV info***"
    sleep 1

    if test -f ./Perf-Verify.conf
    then
        set -o allexport
        source Perf-Verify.conf
        set +o allexport
        if [[ -z $NIC1_VF ]] || [[ -z $NIC2_VF ]]
        then
            fail "NIC_VF Param" "NIC_VF Params not set in Perf-Verify.conf file"
        fi
    else
        fail "Config File" "Cannot locate Perf-Verify.conf"
    fi

    echo "*** Checking for VFs ***"
    if [[ ! `ip a | grep $NIC1_VF` ]] ||  [[ ! `ip a | grep $NIC2_VF` ]]
    then
        fail "NIC_VF Check" "NIC_VF $NIC1_VF or NIC_VF $NIC2_VF cannot be seen by kernel"
    fi

}

OS_checks
append_log
hugepage_checks
sriov_check
conf_checks
config_file_checks
rpm_check
network_connection_check
ovs_running_check

git_clone_vsperf
vsperf_make
customize_VSPerf_code

download_VNF_image
download_conf_files

generate_sriov_conf
run_sriov_tests
print_results_sr_iov
