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

if [ $VERSION_ID == "7.5" ]
then
    dpdk_ver="1711"
    one_queue_image="RHEL7-5VNF-1Q.qcow2"
    two_queue_image="RHEL7-5VNF-2Q.qcow2"
    one_queue_zip="RHEL7-5VNF-1Q.qcow2.lrz"
    two_queue_zip="RHEL7-5VNF-2Q.qcow2.lrz"
elif [ $VERSION_ID == "7.4" ]
then
    dpdk_ver="1705"
    one_queue_image="RHEL7-4VNF-1Q.qcow2"
    two_queue_image="RHEL7-4VNF-1Q.qcow2"
    one_queue_zip="RHEL7-4VNF-1Q.qcow2.lrz"
    two_queue_zip="RHEL7-4VNF-2Q.qcow2.lrz"
fi

OS_checks() {

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

log_folder_check() {
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

}

conf_checks() {

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

}

hugepage_checks() {

    echo "*** Checking Hugepage Config ***"
    sleep 1

    if ! [[ `cat /proc/meminfo | awk /Hugepagesize/ | awk /1048576/` ]]
    then
        fail "Hugepage Check" "Please enable 1G Hugepages"
    fi

}

config_file_checks() {

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

}

nic_card_check() {

    echo "*** Checking for NIC cards ***"
    if [[ ! `ip a | grep $NIC1` ]] ||  [[ ! `ip a | grep $NIC2` ]]


    then
        fail "NIC Check" "NIC $NIC1 or NIC $NIC2 cannot be seen by kernel"
    fi

}

rpm_check() {

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

}

network_connection_check() {

     echo "*** Checking connection to people.redhat.com ***"
     if ping -c 1 people.redhat.com &> /dev/null
     then
         echo "*** Connection to server succesful ***"
     else
         fail "People.redhat.com connection fail" "!!! Cannot connect to people.redhat.com, please verify internet connection !!!"
     fi

}

ovs_running_check() {

     echo "*** Checking for running instance of Openvswitch ***"
     if [ `pgrep ovs-vswitchd` ] || [ `pgrep ovsdb-server` ]
     then
         fail "Openvswitch running" "It appears Openvswitch may be running, please stop all services and processes"
     fi

     cd ~

}

customize_VSPerf_code() {

    echo "*** Customizing VSPerf source code ***"

    # add Trex learning packets
    sed -i '0,/stats = self.generate_traffic(traffic_duration)/s/        stats = self.generate_traffic(traffic, duration)/        self._logger.info("T-Rex sending learning packets")\
        learning_thresh_traffic = copy.deepcopy(traffic)\
        learning_thresh_traffic["frame_rate"] = 1\
        self.generate_traffic(learning_thresh_traffic, 180)\
        self._logger.info("T-Rex finished learning packets")\
        time.sleep(3) # allow packets to complete before starting test traffic\n&/' /root/vswitchperf/tools/pkt_gen/trex/trex.py

    # remove drive sharing
    sed -i "/                     '-drive',$/,+3 d" ~/vswitchperf/vnfs/qemu/qemu.py
    sed -i "/self._copy_fwd_tools_for_all_guests()/c\#self._copy_fwd_tools_for_all_guests()" ~/vswitchperf/testcases/testcase.py

    # add code to deal with custom image
    cat <<EOT >>vnfs/qemu/qemu.py
    def _configure_testpmd(self):
        """
        Configure VM to perform L2 forwarding between NICs by DPDK's testpmd
        """
        #self._configure_copy_sources('DPDK')
        self._configure_disable_firewall()

        # Guest images _should_ have 1024 hugepages by default,
        # but just in case:'''
        self.execute_and_wait('sysctl vm.nr_hugepages={}'.format(S.getValue('GUEST_HUGEPAGES_NR')[self._number]))

        # Mount hugepages
        self.execute_and_wait('mkdir -p /dev/hugepages')
        self.execute_and_wait(
            'mount -t hugetlbfs hugetlbfs /dev/hugepages')

        self.execute_and_wait('cat /proc/meminfo')
        self.execute_and_wait('rpm -ivh ~/dpdkrpms/$dpdk_ver/*.rpm ')
        self.execute_and_wait('cat /proc/cmdline')
        self.execute_and_wait('dpdk-devbind --status')

        # disable network interfaces, so DPDK can take care of them
        for nic in self._nics:
            self.execute_and_wait('ifdown ' + nic['device'])

        self.execute_and_wait('dpdk-bind --status')
        pci_list = ' '.join([nic['pci'] for nic in self._nics])
        self.execute_and_wait('dpdk-devbind -u ' + pci_list)
        self._bind_dpdk_driver(S.getValue(
            'GUEST_DPDK_BIND_DRIVER')[self._number], pci_list)
        self.execute_and_wait('dpdk-devbind --status')

        # get testpmd settings from CLI
        testpmd_params = S.getValue('GUEST_TESTPMD_PARAMS')[self._number]
        if S.getValue('VSWITCH_JUMBO_FRAMES_ENABLED'):
            testpmd_params += ' --max-pkt-len={}'.format(S.getValue(
                'VSWITCH_JUMBO_FRAMES_SIZE'))

        self.execute_and_wait('testpmd {}'.format(testpmd_params), 60, "Done")
        self.execute('set fwd ' + self._testpmd_fwd_mode, 1)
        self.execute_and_wait('start', 20, 'testpmd>')

    def _bind_dpdk_driver(self, driver, pci_slots):
        """
        Bind the virtual nics to the driver specific in the conf file
        :return: None
        """
        if driver == 'uio_pci_generic':
            if S.getValue('VNF') == 'QemuPciPassthrough':
                # unsupported config, bind to igb_uio instead and exit the
                # outer function after completion.
                self._logger.error('SR-IOV does not support uio_pci_generic. '
                                   'Igb_uio will be used instead.')
                self._bind_dpdk_driver('igb_uio_from_src', pci_slots)
                return
            self.execute_and_wait('modprobe uio_pci_generic')
            self.execute_and_wait('dpdk-devbind -b uio_pci_generic '+
                                  pci_slots)
        elif driver == 'vfio_no_iommu':
            self.execute_and_wait('modprobe -r vfio')
            self.execute_and_wait('modprobe -r vfio_iommu_type1')
            self.execute_and_wait('modprobe vfio enable_unsafe_noiommu_mode=Y')
            self.execute_and_wait('modprobe vfio-pci')
            self.execute_and_wait('dpdk-devbind -b vfio-pci ' +
                                  pci_slots)
        elif driver == 'igb_uio_from_src':
            # build and insert igb_uio and rebind interfaces to it
            self.execute_and_wait('make RTE_OUTPUT=$RTE_SDK/$RTE_TARGET -C '
                                  '$RTE_SDK/lib/librte_eal/linuxapp/igb_uio')
            self.execute_and_wait('modprobe uio')
            self.execute_and_wait('insmod %s/kmod/igb_uio.ko' %
                                  S.getValue('RTE_TARGET'))
            self.execute_and_wait('dpdk-devbind -b igb_uio ' + pci_slots)
        else:
            self._logger.error(
                'Unknown driver for binding specified, defaulting to igb_uio')
            self._bind_dpdk_driver('igb_uio_from_src', pci_slots)

EOT
if [ ! -d src/dpdk/dpdk/lib/librte_eal/common/include/ ]
then
    mkdir -p src/dpdk/dpdk/lib/librte_eal/common/include/

cat <<EOT >>src/dpdk/dpdk/lib/librte_eal/common/include/rte_version.h
 /*-
 *   BSD LICENSE
 *
 *   Copyright(c) 2010-2014 Intel Corporation. All rights reserved.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @file
 * Definitions of DPDK version numbers
 */

#ifndef _RTE_VERSION_H_
#define _RTE_VERSION_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <string.h>
#include <rte_common.h>

/**
 * String that appears before the version number
 */
#define RTE_VER_PREFIX "DPDK"

/**
 * Major version/year number i.e. the yy in yy.mm.z
 */
#define RTE_VER_YEAR 16

/**
 * Minor version/month number i.e. the mm in yy.mm.z
 */
#define RTE_VER_MONTH 4

/**
 * Patch level number i.e. the z in yy.mm.z
 */
#define RTE_VER_MINOR 0

/**
 * Extra string to be appended to version number
 */
#define RTE_VER_SUFFIX ""

/**
 * Patch release number
 *   0-15 = release candidates
 *   16   = release
 */
#define RTE_VER_RELEASE 16

/**
 * Macro to compute a version number usable for comparisons
 */
#define RTE_VERSION_NUM(a,b,c,d) ((a) << 24 | (b) << 16 | (c) << 8 | (d))

/**
 * All version numbers in one to compare with RTE_VERSION_NUM()
 */
#define RTE_VERSION RTE_VERSION_NUM( \
			RTE_VER_YEAR, \
			RTE_VER_MONTH, \
			RTE_VER_MINOR, \
			RTE_VER_RELEASE)

/**
 * Function returning version string
 * @return
 *     string
 */
static inline const char *
rte_version(void)
{
	static char version[32];
	if (version[0] != 0)
		return version;
	if (strlen(RTE_VER_SUFFIX) == 0)
		snprintf(version, sizeof(version), "%s %d.%02d.%d",
			RTE_VER_PREFIX,
			RTE_VER_YEAR,
			RTE_VER_MONTH,
			RTE_VER_MINOR);
	else
		snprintf(version, sizeof(version), "%s %d.%02d.%d%s%d",
			RTE_VER_PREFIX,
			RTE_VER_YEAR,
			RTE_VER_MONTH,
			RTE_VER_MINOR,
			RTE_VER_SUFFIX,
			RTE_VER_RELEASE < 16 ?
				RTE_VER_RELEASE :
				RTE_VER_RELEASE - 16);
	return version;
}

#ifdef __cplusplus
}
#endif

#endif /* RTE_VERSION_H */
EOT

fi

}

download_conf_files() {

    echo "*** Creating VSPerf custom conf files ***"

    NIC1_PCI_ADDR=`ethtool -i $NIC1 | awk /bus-info/ | awk {'print $2'}`
    NIC2_PCI_ADDR=`ethtool -i $NIC2 | awk /bus-info/ | awk {'print $2'}`

    NUM_NUMAS=`lscpu | awk /'NUMA node\(s\)'/ | awk {'print $3'}`

    if [ "$NUM_NUMAS" == "2" ]
        then
        SOCKET_MEMORY="['1024', '1024']"
    elif [ "$NUM_NUMAS" == "3" ]
        then
        SOCKET_MEMORY="['1024', '1024', '1024']"
    elif [ "$NUM_NUMAS" == "1" ]
        then
        SOCKET_MEMORY="['1024']"
    fi

    git checkout conf/10_custom.conf --force # reset the config

    cat <<EOT >> ~/vswitchperf/conf/10_custom.conf
VSWITCHD_DPDK_ARGS = ['-c', '0x1', '-n', '4']
VSWITCHD_DPDK_CONFIG = {
    'dpdk-init' : 'true',
    'dpdk-lcore-mask' : '0x1',
}

PATHS['qemu'] = {
    'type' : 'bin',
    'src': {
        'path': os.path.join(ROOT_DIR, 'src/qemu/qemu/'),
        'qemu-system': 'x86_64-softmmu/qemu-system-x86_64'
    },
    'bin': {
        'qemu-system': '/usr/libexec/qemu-kvm'
    }
}

PATHS['vswitch'] = {
    'none' : {      # used by SRIOV tests
        'type' : 'src',
        'src' : {},
    },
    'OvsDpdkVhost': {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/ovs/ovs/'),
            'ovs-vswitchd': 'vswitchd/ovs-vswitchd',
            'ovsdb-server': 'ovsdb/ovsdb-server',
            'ovsdb-tool': 'ovsdb/ovsdb-tool',
            'ovsschema': 'vswitchd/vswitch.ovsschema',
            'ovs-vsctl': 'utilities/ovs-vsctl',
            'ovs-ofctl': 'utilities/ovs-ofctl',
            'ovs-dpctl': 'utilities/ovs-dpctl',
            'ovs-appctl': 'utilities/ovs-appctl',
        },
        'bin': {
            'ovs-vswitchd': 'ovs-vswitchd',
            'ovsdb-server': 'ovsdb-server',
            'ovsdb-tool': 'ovsdb-tool',
            'ovsschema': '/usr/share/openvswitch/vswitch.ovsschema',
            'ovs-vsctl': 'ovs-vsctl',
            'ovs-ofctl': 'ovs-ofctl',
            'ovs-dpctl': 'ovs-dpctl',
            'ovs-appctl': 'ovs-appctl',
        }
    },
    'ovs_var_tmp': '/usr/local/var/run/openvswitch/',
    'ovs_etc_tmp': '/usr/local/etc/openvswitch/',
    'VppDpdkVhost': {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/vpp/vpp/build-root/build-vpp-native'),
            'vpp': 'vpp',
            'vppctl': 'vppctl',
        },
        'bin': {
            'vpp': 'vpp',
            'vppctl': 'vppctl',
        }
    },
}

PATHS['dpdk'] = {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/dpdk/dpdk/'),
            # To use vfio set:
            # 'modules' : ['uio', 'vfio-pci'],
            'modules' : ['uio', os.path.join(RTE_TARGET, 'kmod/igb_uio.ko')],
            'bind-tool': 'tools/dpdk*bind.py',
            'testpmd': os.path.join(RTE_TARGET, 'app', 'testpmd'),
        },
        'bin': {
            'bind-tool': '/usr/share/dpdk/tools/dpdk-devbind.py',
            'modules' : ['uio', 'vfio-pci'],
            'testpmd' : 'testpmd'
        }
    }

PATHS['vswitch'].update({'OvsVanilla' : copy.deepcopy(PATHS['vswitch']['OvsDpdkVhost'])})
PATHS['vswitch']['ovs_var_tmp'] = '/var/run/openvswitch/'
PATHS['vswitch']['ovs_etc_tmp'] = '/etc/openvswitch/'
PATHS['vswitch']['OvsVanilla']['bin']['modules'] = [
        'libcrc32c', 'ip_tunnel', 'vxlan', 'gre', 'nf_nat', 'nf_nat_ipv6',
        'nf_nat_ipv4', 'nf_conntrack', 'nf_defrag_ipv4', 'nf_defrag_ipv6',
        'openvswitch']
PATHS['vswitch']['OvsVanilla']['type'] = 'bin'

GUEST_NIC_MERGE_BUFFERS_DISABLE = [True]

VSWITCH_JUMBO_FRAMES_ENABLED = False
VSWITCH_JUMBO_FRAMES_SIZE = 9000

VSWITCH_DPDK_MULTI_QUEUES = 0
GUEST_NIC_QUEUES = [0]

WHITELIST_NICS = ['$NIC1_PCI_ADDR', '$NIC2_PCI_ADDR']

DPDK_SOCKET_MEM = $SOCKET_MEMORY

VSWITCH_PMD_CPU_MASK = '$PMD2MASK'

GUEST_SMP = ['3']

GUEST_CORE_BINDING = [('$VCPU1', '$VCPU2', '$VCPU3')]

GUEST_IMAGE = ['$one_queue_image']

GUEST_BOOT_DRIVE_TYPE = ['ide']
GUEST_SHARED_DRIVE_TYPE = ['ide']

GUEST_DPDK_BIND_DRIVER = ['vfio_no_iommu']

GUEST_PASSWORD = ['redhat']

GUEST_NICS = [[{'device' : 'eth0', 'mac' : '#MAC(00:00:00:00:00:01,2)', 'pci' : '00:03.0', 'ip' : '#IP(192.168.1.2,4)/24'},
               {'device' : 'eth1', 'mac' : '#MAC(00:00:00:00:00:02,2)', 'pci' : '00:04.0', 'ip' : '#IP(192.168.1.3,4)/24'},
               {'device' : 'eth2', 'mac' : '#MAC(cc:00:00:00:00:01,2)', 'pci' : '00:06.0', 'ip' : '#IP(192.168.1.4,4)/24'},
               {'device' : 'eth3', 'mac' : '#MAC(cc:00:00:00:00:02,2)', 'pci' : '00:07.0', 'ip' : '#IP(192.168.1.5,4)/24'},
             ]]

GUEST_MEMORY = ['8192']

GUEST_HUGEPAGES_NR = ['1']

GUEST_TESTPMD_FWD_MODE = ['io']

GUEST_TESTPMD_PARAMS = ['-l 0,1,2 -n 4 --socket-mem 1024 -- '
                        '--burst=64 -i --txqflags=0xf00 '
                        '--disable-hw-vlan --nb-cores=2, --txq=1 --rxq=1 --rxd=512 --txd=512']

TEST_PARAMS = {'TRAFFICGEN_PKT_SIZES':(64,1500), 'TRAFFICGEN_DURATION':600, 'TRAFFICGEN_LOSSRATE':0}

# Update your Trex trafficgen info below
TRAFFICGEN_TREX_HOST_IP_ADDR = '$TRAFFICGEN_TREX_HOST_IP_ADDR'
TRAFFICGEN_TREX_USER = 'root'
# TRAFFICGEN_TREX_BASE_DIR is the place, where 't-rex-64' file is stored on Trex Server
TRAFFICGEN_TREX_BASE_DIR = '$TRAFFICGEN_TREX_BASE_DIR'
TRAFFICGEN_TREX_PORT1 = '$TRAFFICGEN_TREX_PORT1'
TRAFFICGEN_TREX_PORT2 = '$TRAFFICGEN_TREX_PORT2'
TRAFFICGEN_TREX_LINE_SPEED_GBPS = '$TRAFFICGEN_TREX_LINE_SPEED_GBPS'
TRAFFICGEN = 'Trex'
TRAFFICGEN_TREX_LATENCY_PPS = 0
TRAFFICGEN_TREX_RFC2544_TPUT_THRESHOLD = 0.5

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
        'srcmac': '00:00:00:00:00:00',
        'dstmac': '00:00:00:00:00:00',
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
}

EOT

}

download_VNF_image() {
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

fail() {
    # Param 1, Fail Header
    # Param 2, Fail Message

    echo ""
    echo "!!! $1 FAILED !!!"
    echo "!!! $2 !!!"
    echo ""
    exit 1

}

generate_2queue_conf() {

cat <<EOT >>/root/vswitchperf/twoqueue.conf
GUEST_TESTPMD_PARAMS = ['-l 0,1,2,3,4 -n 4 --socket-mem 512 -- '
                        '--burst=64 -i --txqflags=0xf00 '
                        '--disable-hw-vlan --nb-cores=4, --txq=2 --rxq=2 --rxd=512 --txd=512']

VSWITCH_PMD_CPU_MASK = '$PMD4MASK'

GUEST_SMP = ['5']

GUEST_CORE_BINDING = [('$VCPU1', '$VCPU2', '$VCPU3', '$VCPU4', '$VCPU5')]

GUEST_IMAGE = ['$two_queue_image']

VSWITCH_DPDK_MULTI_QUEUES = 2
GUEST_NIC_QUEUES = [2]

EOT

}

git_clone_vsperf() {
    if ! [ -d "vswitchperf" ]
    then
        echo "*** Cloning OPNFV VSPerf project ***"

        yum install -y git &>$NIC_LOG_FOLDER/vsperf_clone.log
        git clone https://gerrit.opnfv.org/gerrit/vswitchperf &>>$NIC_LOG_FOLDER/vsperf_clone.log
    fi
    cd vswitchperf
    git checkout -f 9d2900035923bf307477c5b4b8dc423ba1b2086f &>>$NIC_LOG_FOLDER/vsperf_clone.log # Euphrates release
    git fetch https://gerrit.opnfv.org/gerrit/vswitchperf refs/changes/75/44275/1 && git cherry-pick FETCH_HEAD # single numa fix
    git fetch https://gerrit.opnfv.org/gerrit/vswitchperf refs/changes/47/44247/7 && git cherry-pick FETCH_HEAD # T-Rex multistream


}

run_ovs_dpdk_tests() {

DONOTFAIL=$1

    echo ""
    echo "***********************************************************"
    echo "*** Running 64/1500 Bytes 2PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "***********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput &>$NIC_LOG_FOLDER/vsperf_pvp_2pmd.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" $NIC_LOG_FOLDER/vsperf_pvp_2pmd.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 3000000 ]
        then
            echo "# 64   Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes 2 PMD OVS/DPDK PVP failed to reach required 3.5 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 1500000 ]
        then
            echo "# 1500 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes 2 PMD OVS/DPDK PVP failed to reach required 1.5 Mpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 3000000 ] || [ "${array[1]%%.*}" -lt 1500000 ]
        then
            if [ $DONOTFAIL -eq 0 ]
            then
                fail "64/1500 Byte 2PMD PVP" "Failed to achieve required pps on tests"
            fi
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at $NIC_LOG_FOLDER/vsperf_pvp_2pmd.log"
    fi

    echo ""
    echo "***********************************************************"
    echo "*** Running 64/1500 Bytes 2 queue 4PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "***********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --conf-file=/root/vswitchperf/twoqueue.conf &>$NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" $NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 6000000 ]
        then
            echo "# 64   Byte 2 queue 4PMD OVS/DPDK PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes 2 queue 4 PMD OVS/DPDK PVP failed to reach required 6.0 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 1500000 ]
        then
            echo "# 1500 Byte 2 queue 4PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes 2 queue 4 PMD OVS/DPDK PVP failed to reach required 1.5 Mpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 6000000 ] || [ "${array[1]%%.*}" -lt 1500000 ]
        then
            if [ $DONOTFAIL -eq 0 ]
            then
                fail "64/1500 Byte 2 queue 4PMD PVP" "Failed to achieve required pps on tests"
            fi
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at $NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log"
    fi

    echo ""
    echo "*****************************************************************"
    echo "*** Running 2000/9000 Bytes 2PMD PVP OVS/DPDK VSPerf TEST     ***"
    echo "*****************************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --test-params="TRAFFICGEN_PKT_SIZES=2000,9000; VSWITCH_JUMBO_FRAMES_ENABLED=True" &>$NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" $NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 1100000 ]
        then
            echo "# 2000 Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #"
        else
            echo "# 2000 Bytes 2 PMD OVS/DPDK PVP failed to reach required 1.1 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 250000 ]
        then
            echo "# 9000 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 9000 Bytes 2 PMD OVS/DPDK PVP failed to reach required 250 Kpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 1100000 ] || [ "${array[1]%%.*}" -lt 250000 ]
        then
            if [ $DONOTFAIL -eq 0 ]
            then
                fail "2000/9000 Byte 2PMD PVP" "Failed to achieve required pps on tests"
            fi
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at $NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log"
    fi

}

run_ovs_kernel_tests() {
    echo ""
    echo "********************************************************"
    echo "*** Running 64/1500 Bytes PVP OVS Kernel VSPerf TEST ***"
    echo "********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
python ./vsperf pvp_tput --vswitch=OvsVanilla --vnf=QemuVirtioNet --test-params="TRAFFICGEN_LOSSRATE=0.002" &>$NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" $NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 100000 ]
        then
            echo "# 64   Byte OVS Kernel PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes OVS Kernel PVP failed to reach required 100 Kpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 100000 ]
        then
            echo "# 1500 Byte OVS Kernel PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes OVS Kernel PVP failed to reach required 200 Kpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 100000 ] || [ "${array[1]%%.*}" -lt 100000 ]
        then
            if [ $DONOTFAIL -eq 0 ]
            then
                fail "64/1500 OVS Kernel PVP" "Failed to achieve required pps on tests"
            fi
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at $NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log"
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

mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
########################################################
#             RESULTS OF ALL VSPERF TESTS              #
#                                                      #
# 64   Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #
# 1500 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #
EOT

mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_4pmd-2q.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte 4PMD 2Q OVS/DPDK PVP test result: ${array[0]} #
# 1500 Byte 4PMD 2Q OVS/DPDK PVP test result: ${array[1]} #
EOT

mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_2pmd_jumbo.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 2000 Byte 2PMD OVS/DPDK Phy2Phy test result: ${array[0]} #
# 9000 Byte 2PMD OVS/DPDK Phy2Phy test result: ${array[1]} #
EOT

mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" $NIC_LOG_FOLDER/vsperf_pvp_ovs_kernel.log | awk '{print $11}' )
cat <<EOT >>$NIC_LOG_FOLDER/vsperf_results.txt
# 64   Byte OVS Kernel PVP test result: ${array[0]} #
# 1500 Byte OVS Kernel PVP test result: ${array[0]} #
#####################################################
EOT

cat $NIC_LOG_FOLDER//vsperf_results.txt

}

copy_config_files_to_log_folder() {

cp /root/vswitchperf/conf/* $NIC_LOG_FOLDER
cp /root/RHEL_NIC_QUALIFICATION/Perf-Verify.conf $NIC_LOG_FOLDER

}

main() {
if [ "${1}" == "--donotfail" ]
then
    DONOTFAIL=1
else
    DONOTFAIL=0
fi
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

git_clone_vsperf
vsperf_make
customize_VSPerf_code
download_VNF_image
download_conf_files
generate_2queue_conf
run_ovs_dpdk_tests $DONOTFAIL
run_ovs_kernel_tests $DONOTFAIL
print_results
copy_config_files_to_log_folder
}

if [ "${1}" != "--source-only" ]
then
    main "${@}"
fi