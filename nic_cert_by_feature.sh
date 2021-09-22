#!/bin/bash
. env.sh
. ovs-perf-test/ovs_perf_runtest.sh


#Set up the settings for ovs_perf and throughput tests. And install Trex.




throughput_dut_init()
{
    #ssh root@$DUT "yum -y install openvswitch2.15 openvswitch-selinux-extra-policy dpdk dpdk-tools"
    ssh root@$DUT <<-EOF
		yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm git wget python3 hwloc hwloc-gui grubby tuned-profiles-cpu-partitioning
		alternatives --set python /usr/bin/python3
		pip3 install lxml
		yum -y install $ovs_rpm_path $ovs_selinux_rpm_path $dpdk_rpm_path $dpdk_tools_rpm_path
		git clone -b feature-cert --single-branch https://github.com/ctrautma/RHEL_NIC_QUALIFICATION.git
		yum install -y ~/RHEL_NIC_QUALIFICATION/throughput-test/lrzip-0.616-5.el7.x86_64.rpm
		cp /root/test_env.sh /root/RHEL_NIC_QUALIFICATION/throughput-test/
		grubby --args='intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32' --update-kernel=$(grubby --default-kernel)
		pushd ~/RHEL_NIC_QUALIFICATION/throughput-test
		bash -x write_tuned_cpu-partitioning-variables_conf.sh
		tuned-adm profile cpu-partitioning
		systemctl enable tuned
	EOF

    ssh root@$DUT "reboot"
    
    sleep 60

    while ! ping -c 1 $DUT &>/dev/null; do
        sleep 5
    done
    sleep 60
}

sriov_tests()
{
    #Start throughput tests

    throughput_dut_init
    
    #yum -y install $ovs_rpm_path $ovs_selinux_rpm_path $dpdk_rpm_path $dpdk_tools_rpm_path

    cat > throughput_test_items.sh <<-EOF
		SKIP_SRIOV=0
		SKIP_1Q=1
		SKIP_2Q=1
		SKIP_JUMBO=1
		SKIP_KERNEL=1
	EOF

    scp throughput_test_items.sh root@$DUT:/root/RHEL_NIC_QUALIFICATION/throughput-test
    


    ssh root@$DUT  <<-EOF
		echo 1 > /sys/bus/pci/devices/$dut_interface_1_pciid/sriov_numvfs
		echo 1 > /sys/bus/pci/devices/$dut_interface_2_pciid/sriov_numvfs
		ip link set $dut_interface_1 vf 0 spoofchk off
		ip link set $dut_interface_2 vf 0 spoofchk off
		ip link set $dut_interface_1 vf 0 trust on
		ip link set $dut_interface_2 vf 0 trust on
		ip link show $dut_interface_1
		ip link show $dut_interface_2
	EOF

    ssh root@$DUT  <<-EOF
		pushd /root/RHEL_NIC_QUALIFICATION/throughput-test
		cp /root/throughput_test_items.sh ./
		./main-perf-test.sh
	EOF
}

echo "#############"
echo "#OVS-DPDK tests"
echo "#############"





ovs_dpdk_tests()
{

    #start ovs_perf tests
    pft_pvp_ovsdpdk

    #start throughput tests

    throughput_dut_init

    cat > throughput_test_items.sh <<-EOF
		SKIP_SRIOV=1
		SKIP_1Q=0
		SKIP_2Q=0
		SKIP_JUMBO=0
		SKIP_KERNEL=1
	EOF
    scp throughput_test_items.sh root@$DUT:/root/RHEL_NIC_QUALIFICATION/throughput-test
  
    ssh root@$DUT  <<-EOF
		pushd /root/RHEL_NIC_QUALIFICATION/throughput-test
        cp /root/throughput_test_items.sh ./
        ./main-perf-test.sh
	EOF

}

ovs_kernel_tests()
{
    pft_pvp_kernel

    throughput_dut_init

        cat > throughput_test_items.sh <<-EOF
		SKIP_SRIOV=1
		SKIP_1Q=1
		SKIP_2Q=1
		SKIP_JUMBO=1
		SKIP_KERNEL=0
	EOF
    scp throughput_test_items.sh root@$DUT:/root/RHEL_NIC_QUALIFICATION/throughput-test
    ssh root@$DUT  <<-EOF
		pushd /root/RHEL_NIC_QUALIFICATION/throughput-test
		cp /root/throughput_test_items.sh ./
		./main-perf-test.sh
	EOF
}


hwol_tests()
# pvp tests
{
    pft_pvp_tcflower_offload

    pft_tc_flow_insertion
  

}

pft_setup

if [ "$SRIOV_TEST" = true ]; then
    echo "##########################"
    echo "#start SRIOV tests"
    echo "##########################"
    sriov_tests
fi    
    
if [ "$OVS_KERNEL_TEST" = true ]; then
    echo "##########################"
    echo "#start OVS-Kernel tests"
    echo "##########################"
    ovs_kernel_tests
fi  

if [ "$OVS_DPDK_TEST" = true ]; then
    echo "##########################"
    echo "#start OVS-DPDK tests"
    echo "##########################"
    ovs_dpdk_tests
fi  

if [ "$HWOL_TEST" = true ]; then
    echo "##########################"
    echo "#starts Hardware offload (HWOL) tests"
    echo "##########################"
    hwol_tests
fi  
