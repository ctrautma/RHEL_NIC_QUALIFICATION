#!/bin/bash

dev_pci=$1
func_name=$2

if [ x"$dev_pci" == x"" ]
then
	exit 1
fi

if [ x"$func_name" == x"" ]
then
	exit 1
fi

if ! lspci -D | grep $dev_pci &> /dev/null
then
	exit 1
fi

nofunc=1
for name in dut_isolated_cpus dut_dpdk_pmd_mask dut_pmd_rxq_affinity vcpu_1 vcpu_2 vcpu_3 vcpu_4
do
	if [ $func_name == $name ]
	then
		nofunc=0
		break
	fi
done

if [ $nofunc -eq 1 ]
then
	exit 1
fi

dev_numa_node=$(lspci  -s $dev_pci -v | grep -o "NUMA node [0-9]*" | awk '{print $3}')
numa_cpulist=$(lscpu | grep "NUMA node${dev_numa_node}" | awk '{print $4}')
first_ht_pair=$(cat /sys/devices/system/cpu/cpu${dev_numa_node}/topology/thread_siblings_list | tr , " ")
dut_isolated_cpus=$numa_cpulist

for cpu in $first_ht_pair
do
	dut_isolated_cpus=$(echo $dut_isolated_cpus | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done
pmd_cpu_0=$(echo $dut_isolated_cpus | awk -F, '{print $1}')
pmd_cpu_full=$(cat /sys/devices/system/cpu/cpu${pmd_cpu_0}/topology/thread_siblings_list | tr , " ")
pmd_cpu_1=$(echo $pmd_cpu_full | awk '{print $2}')

remaining_cpus=$dut_isolated_cpus

for cpu in $pmd_cpu_full
do
	remaining_cpus=$(echo $remaining_cpus | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done

pmd_mask()
{
	cpus=$1
	read -a arr <<<$cpus
	foo="'p/x "
	for i in "${arr[@]}"
	do
		foo="$foo 1ULL<<$i |"
	done
	foo=`echo $foo | rev | cut -c 2- | rev`
	foo="echo $foo ' | gdb"
	eval "${foo}" >mask.txt
	cat mask.txt | awk /=/ | awk '{print $4}'
}

dut_isolated_cpus()
{
	echo $dut_isolated_cpus
}

dut_dpdk_pmd_mask()
{
	pmd_mask "$pmd_cpu_full"
}

dut_pmd_rxq_affinity()
{
	echo "0:$pmd_cpu_0,1:$pmd_cpu_1"
}

vcpu_1()
{
	echo $remaining_cpus | awk -F, '{print $1}'
}

vcpu_2()
{
	echo $remaining_cpus | awk -F, '{print $2}'
}

vcpu_3()
{
	echo $remaining_cpus | awk -F, '{print $3}'
}

vcpu_4()
{
	echo $remaining_cpus | awk -F, '{print $4}'
}

$func_name
