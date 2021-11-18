#!/bin/bash



show_env()
{
	echo ANSIBLE_CONTROLLER=$ANSIBLE_CONTROLLER
	echo DUT=$DUT
	echo TESTER=$TESTER
	echo MYSELF=$(hostname)

	echo nic_speed=$nic_speed
	echo trex_url=$trex_url
	echo trex_interface_1=$trex_interface_1
	echo trex_interface_2=$trex_interface_2
	echo dut_interface_1=$dut_interface_1
	echo dut_interface_2=$dut_interface_2
	echo dut_interface_1_pciid=$dut_interface_1_pciid

	echo pf_representor=$pf_representor
	echo vf_representor=$vf_representor

	echo ovs_rpm_path=$ovs_rpm_path
	echo ovs_selinux_rpm_path=$ovs_selinux_rpm_path
	echo dpdk_rpm_path=$dpdk_rpm_path
	echo dpdk_tools_rpm_path=$dpdk_tools_rpm_path

	echo guest_image=$guest_image
	echo rhel_guest_image_path=$rhel_guest_image_path

	echo rh_nic_cert=$rh_nic_cert
	echo pkg_netperf=$pkg_netperf
	echo iperf_rpm_path=$iperf_rpm_path

	echo QE_SKIP_OVS_BOND_TEST=$QE_SKIP_OVS_BOND_TEST

	echo CLIENTS=$CLIENTS
	echo SERVERS=$SERVERS
	echo NIC_CLIENT=$NIC_CLIENT
	echo NIC_SERVER=$NIC_SERVER
	echo IMG_GUEST=$IMG_GUEST
	echo SRC_NETPERF=$SRC_NETPERF
	echo IPERF_RPM=$IPERF_RPM
	echo RPM_OVS_SELINUX_EXTRA_POLICY=$RPM_OVS_SELINUX_EXTRA_POLICY
	echo RPM_OVS=$RPM_OVS
	echo RPM_DPDK=$RPM_DPDK
	echo RPM_DPDK_TOOLS=$RPM_DPDK_TOOLS

}

trex_install()
{

	# temparory workaround for fail to install python3_devel in trex_setup.yml
	if [[ -n "$rpm_python3_devel" ]]
	then
		ssh root@$TESTER "yum -y install $rpm_python3_devel"
	fi
		ssh root@$TESTER "yum -y install python3; python3 -m pip install -U pip; pip3 install python-tripleoclient --ignore-installed PyYAML"
	# run ansible play book to install trex
	pushd ~/RHEL_NIC_QUALIFICATION/common
	ansible-playbook trex_setup.yml
	popd
}


pft_setup()
{
	local result=0

	echo "$FUNCNAME() ..."

	[[ x"$ANSIBLE_CONTROLLER" != x"$(hostname)" ]] && return 0

	show_env

	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
	yum -y install python3 git sshpass wget
	python3 -m pip install -U pip
	pip3 install ansible

	#git clone -b feature-cert --single-branch https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
	#pushd RHEL_NIC_QUALIFICATION/
	#git checkout -b feature-cert remotes/origin/ansible
	#git submodule update --init
	#popd

	pushd ~/RHEL_NIC_QUALIFICATION/common
	cat > ansible.cfg <<-EOF
		[defaults]
		inventory=./inventory
		remote_user=root
		verbosity=2
		stdout_callback = debug
	EOF
	cat > inventory <<-EOF
		[trex]
		$TESTER
		[dut]
		$DUT
	EOF
	cat > test_settings.yml <<-EOF
		redhat_debug_mode: True
		qe_subscription_mode: true
		qe_subscription_command: "$qe_subscription_command"
		trex_url: $trex_url
		trex_interface_1: $trex_interface_1
		trex_interface_2: $trex_interface_2
		ovs_rpm_path: "$ovs_rpm_path"
		ovs_selinux_rpm_path: "$ovs_selinux_rpm_path"
		dpdk_rpm_path: "$dpdk_rpm_path"
		dpdk_tools_rpm_path: "$dpdk_tools_rpm_path"
		dut_interface_1: $dut_interface_1
		dut_interface_2: $dut_interface_2
		dut_interface_1_pciid: "$dut_interface_1_pciid"
		dut_interface_2_pciid: "$dut_interface_2_pciid"
		dut_driver_override: vfio-pci
		dut_cpu_model: host
		vm_driver_override: vfio-pci
		vm_interface_1_pciid: "0000:00:01.0"
		vm_interface_2_pciid: "0000:00:02.0"
		vm_isolated_cpus: 1-3
		rhel_guest_image_path: $rhel_guest_image_path
		trex_linux_cmdline: "intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32"
		dut_linux_cmdline: "intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32"
	EOF
	cp ansible.cfg ~/RHEL_NIC_QUALIFICATION/ovs-perf-test/
	cp test_settings.yml ~/RHEL_NIC_QUALIFICATION/ovs-perf-test/
	cp inventory ~/RHEL_NIC_QUALIFICATION/ovs-perf-test/
	
	popd

	[[ -f /root/.ssh/id_rsa ]] || ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""
	sshpass -p "$login_passwd" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@${DUT}
	sshpass -p "$login_passwd" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@${TESTER}

	# temparory workaround for fail to install python3_devel in trex_setup.yml
#	if [[ -n "$rpm_python3_devel" ]]
#	then
#		ssh root@$TESTER "yum -y install $rpm_python3_devel"
#	fi
    
#	ssh root@$TESTER "yum -y install python3; python3 -m pip install -U pip; pip3 install python-tripleoclient --ignore-installed PyYAML"
    

#    # run ansible play book to install trex
#	pushd ~/RHEL_NIC_QUALIFICATION/common
#	ansible-playbook trex_setup.yml
#	popd

	ssh root@$DUT <<-EOF
		yum -y install wget
		wget -nv -N --no-cache ${guest_image}
	EOF

	cat > /root/test_env.sh <<-EOF
		set -a
		nic_speed=$nic_speed
		trex_url=$trex_url
		trex_interface_1=$trex_interface_1
		trex_interface_2=$trex_interface_2
		trex_interface_1_mac=$trex_interface_1_mac
		trex_interface_2_mac=$trex_interface_2_mac
		dut_interface_1=$dut_interface_1
		dut_interface_2=$dut_interface_2
		dut_interface_1_pciid=$dut_interface_1_pciid
		dut_interface_2_pciid=$dut_interface_2_pciid
		pf_representor=$pf_representor
		vf_representor=$vf_representor
		ovs_rpm_path=$ovs_rpm_path
		ovs_selinux_rpm_path=$ovs_selinux_rpm_path
		dpdk_rpm_path=$dpdk_rpm_path
		dpdk_tools_rpm_path=$dpdk_tools_rpm_path
		guest_image=$guest_image
		rhel_guest_image_path=$rhel_guest_image_path
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
		#RPM_DRIVERCTL=
		# throughput test variables
		QE_SKIP_OVS_BOND_TEST="yes"
		ONE_QUEUE_IMAGE=$ONE_QUEUE_IMAGE
		TWO_QUEUE_IMAGE=$TWO_QUEUE_IMAGE
		DPDK_VER=$DPDK_VER
		#DPDK_URL=$dpdk_rpm_path
		#DPDK_TOOL_URL=$dpdk_tools_rpm_path
		#TREX_URL=$trex_url
		#TRAFFICGEN_TREX_HOST_IP_ADDR=$TESTER
		
		
	EOF
	scp /root/test_env.sh root@$DUT:/root/
	scp /root/test_env.sh root@$TESTER:/root/

	return $result
}
