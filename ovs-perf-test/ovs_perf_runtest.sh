
#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/nic_certificate/pft_auto/ansible
#   Description: PFT ansible tests
#   Author: qding@redhat.com
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

# Include Beaker environment
#. /mnt/tests/kernel/networking/common/include.sh || exit 1

#. /mnt/tests/kernel/networking/common/lib/lib_nc_sync.sh || exit 1


pft_pvp_ovsdpdk()
{
	local result=0

	echo "$FUNCNAME() ..."

	[[ x"$ANSIBLE_CONTROLLER" != x"$(hostname)" ]] && return 0

	[[ -f /root/test_env.sh ]] && source /root/test_env.sh
	show_env

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		nohup ./t-rex-64 -c 4 -i --no-ofed-check &>/tmp/t_rex_64.log &
		sleep 10
		ps -ef | grep t-rex
		popd
	EOF

	ssh root@$DUT "yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm git wget python3 hwloc hwloc-gui grubby tuned-profiles-cpu-partitioning python3; \
	python3 -m pip install -U pip; pip3 install lxml"
	
	pushd /root/RHEL_NIC_QUALIFICATION/ovs-perf-test/
	ansible-playbook pvp_ovsdpdk.yml
	popd

	local dut_ip=$(getent hosts $DUT | awk '{ print $1 }')
	echo dut_ip=${dut_ip}

	ssh root@$TESTER <<-EOF
		pushd /root/pvp_results
		~/ovs_perf/ovs_performance.py \
			-d -l testrun_log.txt \
			--tester-type trex \
			--tester-address localhost \
			--tester-interface 0 \
			--ovs-address ${dut_ip} \
			--ovs-user root \
			--ovs-password ${login_passwd} \
			--dut-vm-address 192.168.122.5 \
			--dut-vm-user root \
			--dut-vm-password root \
			--dut-vm-nic-queues=2 \
			--physical-interface dpdk0 \
			--physical-speed=10 \
			--virtual-interface vhost0 \
			--dut-vm-nic-pci=0000:00:02.0 \
			--packet-list=64 \
			--stream-list=1000 \
			--no-bridge-config \
			--skip-pv-test
		popd
	EOF

	if [[ "$RUNFULLDAY" != 'no' ]]
	then
		ssh root@$TESTER <<-EOF
			pushd /root/ovs_perf
			echo -e "dpdk\n${dut_ip}\n${login_passwd}\n192.168.122.5\nroot\nlocalhost\ndpdk0\nvhost0\n0000:00:02.0\n4096\n1024\n0\n${nic_speed}\n10,1000,10000,100000,1000000" | ./runfullday.sh
			popd
		EOF
	else
		echo "Warning: runfullday.sh is skipped!"
	fi

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		popd
	EOF

	scp root@${TESTER}:/root/pvp_results_*_dpdk.tgz .
	local f_result=''
	for f_result in $(ls pvp_results_*_dpdk.tgz)
	do
		rhts_submit_log -l $f_result
	done

	return $result
}

pft_pvp_kernel()
{
	local result=0

	echo "$FUNCNAME() ..."

	[[ x"$ANSIBLE_CONTROLLER" != x"$(hostname)" ]] && return 0

	[[ -f /root/test_env.sh ]] && source /root/test_env.sh
	show_env

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		nohup ./t-rex-64 -c 4 -i --no-ofed-check &>/tmp/t_rex_64.log &
		sleep 10
		ps -ef | grep t-rex
		popd
	EOF

	pushd RHEL_NIC_QUALIFICATION/ovs-perf-test
	ansible-playbook pvp_kernel.yml
	popd

	local dut_ip=$(getent hosts $DUT | awk '{ print $1 }')

	ssh root@$TESTER <<-EOF
		pushd /root/pvp_results
		~/ovs_perf/ovs_performance.py \
			-d -l testrun_log.txt \
			--tester-type trex \
			--tester-address localhost \
			--tester-interface 0 \
			--ovs-address ${dut_ip} \
			--ovs-user root \
			--ovs-password ${login_passwd} \
			--dut-vm-address 192.168.122.5 \
			--dut-vm-user root \
			--dut-vm-password root \
			--physical-interface ${dut_interface_1} \
			--virtual-interface vnet0 \
			--dut-vm-nic-pci=0000:00:02.0 \
			--packet-list=64 \
			--stream-list=1000 \
			--no-bridge-config \
			--skip-pv-test \
			--testpmd-startup-delay=10
		popd
	EOF

	if [[ "$RUNFULLDAY" != 'no' ]]
	then
		ssh root@$TESTER <<-EOF
			pushd /root/ovs_perf
			echo -e "kernel\n${dut_ip}\n${login_passwd}\n192.168.122.5\nroot\nlocalhost\n${dut_interface_1}\nvnet0\n0000:00:02.0\n4096\n1024\n0\n${nic_speed}\n10,1000,10000,100000,1000000" | ./runfullday.sh
			popd
		EOF
	else
		echo "Warning: runfullday.sh is skipped!"
	fi

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		popd
	EOF

	scp root@${TESTER}:/root/pvp_results_*_kernel.tgz .
	local f_result=''
	for f_result in $(ls pvp_results_*_kernel.tgz)
	do
		rhts_submit_log -l $f_result
	done

	return $result
}

pft_pvp_tcflower_offload()
{
	local result=0

	echo "$FUNCNAME() ..."

	[[ x"$ANSIBLE_CONTROLLER" != x"$(hostname)" ]] && return 0

	[[ -f /root/test_env.sh ]] && source /root/test_env.sh
	show_env

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		nohup ./t-rex-64 -c 4 -i --no-ofed-check &>/tmp/t_rex_64.log &
		sleep 10
		ps -ef | grep t-rex
		popd
	EOF

	pushd RHEL_NIC_QUALIFICATION/ovs-perf-test
	ansible-playbook pvp_tcflower_offload.yml
	popd

	local dut_ip=$(getent hosts $DUT | awk '{ print $1 }')

	ssh root@$TESTER <<-EOF
		pushd /root/pvp_results
		~/ovs_perf/ovs_performance.py \
			-d -l testrun_log.txt \
			--tester-type trex \
			--tester-address localhost \
			--tester-interface 0 \
			--ovs-address ${dut_ip} \
			--ovs-user root \
			--ovs-password ${login_passwd} \
			--dut-vm-address 192.168.122.5 \
			--dut-vm-user root \
			--dut-vm-password root \
			--physical-interface ${pf_representor} \
			--virtual-interface ${vf_representor} \
			--dut-vm-nic-pci=0000:00:04.0 \
			--stream-list=1000 \
			--packet-list=64 \
			--no-bridge-config \
			--skip-pv-test \
			--testpmd-startup-delay=10
		popd
	EOF

	if [[ "$RUNFULLDAY" != 'no' ]]
	then
		ssh root@$TESTER <<-EOF
			pushd /root/ovs_perf
			echo -e "tc\n${dut_ip}\n${login_passwd}\n192.168.122.5\nroot\nlocalhost\n${pf_representor}\n${vf_representor}\n0000:00:04.0\n4096\n1024\n0\n${nic_speed}\n10,1000,10000,100000,1000000" | ./runfullday.sh
			popd
		EOF
	else
		echo "Warning: runfullday.sh is skipped!"
	fi

	ssh root@$TESTER <<-EOF
		pushd /root/trex/v*/
		pkill -f t-rex
		sleep 2
		popd
	EOF

	scp root@${TESTER}:/root/pvp_results_*_tc.tgz .
	local f_result=''
	for f_result in $(ls pvp_results_*_tc.tgz)
	do
		rhts_submit_log -l $f_result
	done

	return $result
} 

pft_tc_flow_insertion()
{
	local result=0

	echo "$FUNCNAME() ..."

	[[ x"$ANSIBLE_CONTROLLER" != x"$(hostname)" ]] && return 0

	[[ -f /root/test_env.sh ]] && source /root/test_env.sh
	show_env

	pushd RHEL_NIC_QUALIFICATION/ovs-perf-test
	ansible-playbook tc_flow_insertion.yml
	popd

	ssh -tt root@$DUT <<-EOF
		virsh list --all | sed -n 3~1p | awk '/[[:alpha:]]+/ {
			system("virsh destroy "\$2)
			sleep 2
			system("virsh undefine "\$2" &>/dev/null")
		}'

		echo 0 > /sys/bus/pci/devices/${dut_interface_1_pciid}/sriov_numvfs
		sleep 30
		ip link show

		pushd RHEL_NIC_QUALIFICATION/perf-flower/rule-install-rate/
		./run.sh -i ${dut_interface_1}
		tar cvzf tc_flow_insertion.tgz fl_change.* perf.data
		popd
		exit
	EOF

	scp root@${DUT}:/root/RHEL_NIC_QUALIFICATION/perf-flower/rule-install-rate/tc_flow_insertion.tgz .
	rhts_submit_log -l tc_flow_insertion.tgz

	return $result
}

_pft_functionality()
{
	local result=0

	echo "$FUNCNAME() ..."

	if [[ -n "$ANSIBLE_CONTROLLER" ]] && [[ x"$ANSIBLE_CONTROLLER" == x"$(hostname)" ]]
	then
		sync_set "$DUT $TESTER" $FUNCNAME
		sync_wait "$DUT $TESTER" $FUNCNAME 129600
	else

		if (($REBOOTCOUNT == 0))
		then
			[[ -n "$ANSIBLE_CONTROLLER" ]] && sync_wait "$ANSIBLE_CONTROLLER" $FUNCNAME
		fi

		if [[ -f /root/test_env.sh ]]
		then
			cat /root/test_env.sh
			source /root/test_env.sh
		else
			set -a
			CLIENTS=$DUT
			SERVERS=$TESTER
			NIC_CLIENT="$dut_interface_1 $dut_interface_2"
			NIC_SERVER="$trex_interface_1"
			IMG_GUEST=$guest_image
			SRC_NETPERF=$pkg_netperf
			IPERF_RPM=$iperf_rpm_path
			RPM_OVS_SELINUX_EXTRA_POLICY=$ovs_selinux_rpm_path
			RPM_OVS=$ovs_rpm_path
			RPM_DPDK=$dpdk_rpm_path
			RPM_DPDK_TOOLS=$dpdk_tools_rpm_path
		fi
		show_env

		if [[ x"$DUT" == x"$(hostname)" ]]
		then
			nmcli dev set ${dut_interface_1}  managed no
			nmcli dev set ${dut_interface_2}  managed no
		elif [[ x"$TESTER" == x"$(hostname)" ]]
		then
			nmcli dev set ${trex_interface_1}  managed no
			nmcli dev set ${trex_interface_2}  managed no
		fi

		yum -y install wget git
		pushd /root/
		[[ -e RHEL_NIC_QUALIFICATION ]] || git clone https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
		pushd RHEL_NIC_QUALIFICATION/
		rm -rf $(basename ${rh_nic_cert})
		wget -nv -N --no-cache ${rh_nic_cert}
		tar xf $(basename ${rh_nic_cert})
		pushd $(basename -s.tar ${rh_nic_cert})

		./rh_nic_cert.sh

		popd
		./collection.sh
		rhts_submit_log -l "$(ls $(hostname)_*.tar)"
		popd
		popd

		[[ -n "$ANSIBLE_CONTROLLER" ]] && sync_set "$ANSIBLE_CONTROLLER" $FUNCNAME
	fi

	return $result
}

################################################################
# main

#rlJournalStart

#if [[ x"$ANSIBLE_CONTROLLER" == x"$(hostname)" ]]
#then
#	sync_wait "$DUT $TESTER" pft_start 300

#	rlPhaseStartSetup
#	rlRun "pft_setup"
#	rlPhaseEnd

#	_test_list=$(sed -n '/^pft_/ s/(.*$//p' $0)

#	for i in $_test_list
#	do
#		if echo "$PFT_SKIP" | grep -e "\b${i}\b" &>/dev/null
#		then
#			echo "$i is skipped"
#			continue
#		fi

#		if [[ "$PFT_TEST" == "$i" ]] || [[ "$PFT_TEST" == "PFT_ALL" ]]
#		then
#			rlPhaseStartTest "$i"
#			rlRun "$i"
#			rlPhaseEnd
#		fi
#	done

#	sync_set "$DUT $TESTER" pft_end 300
#else
#	(($REBOOTCOUNT == 0)) && sync_set $ANSIBLE_CONTROLLER pft_start 300
#	sync_wait1 $ANSIBLE_CONTROLLER pft_end 604800
#fi

#rlJournalPrintText
#rlJournalEnd
