#!/bin/bash

# Uncomment to enable debugging
# set -xv

# Converts a range of CPUs into an array.
# For example, "0-3,7" becomes "0,1,2,3,7".
# Requires two arguments:
# $1 - The string to be expanded
# $2 - The list of CPUs being returned
function parse_range {
	arr=()
  IFS=', ' read -a ranges <<< $1
  for range in "${ranges[@]}"; do
    IFS=- read start end <<< "$range"
    [ -z "$start" ] && continue
    [ -z "$end" ] && end=$start
    for ((i = start; i <= end; i++)); do
			arr+=($i)
    done
  done
  eval $2=$(IFS=,;printf "%s" "${arr[*]}")
}

# Compacts an array of CPUs into a range.
# For example, "0,1,2,3,7" becomes "0-3,7".
# Requires two arguments:
# $1 - The string to be compacted
# $2 - The list of CPUs being returned
function compact_range {
	arr=()
	start=""
	for cpu in ${1//,/ }; do
		[ -z "$start" ] && start=$cpu && range=$cpu && last=$cpu && continue
		prev=$(( $cpu - 1 ))
		[ "$prev" -ne "$last" ] && arr+=($range) && start=$cpu && range=$cpu && last=$cpu && continue
		range="${start}-${cpu}" && last=$cpu
	done
	arr+=($range)
  eval $2=$(IFS=,;printf "%s" "${arr[*]}")
}

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
for name in dut_isolated_cpus dut_dpdk_pmd_mask dut_pmd_rxq_affinity vcpu_0 vcpu_1 vcpu_2 vcpu_3 vcpu_4 vcpu_5 vcpu_6 vcpu_7 dut_dpdk_lcore_mask vcpu_str vcpu_emulator vcpu_count numa_node driver_queues
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

# Make sure the system has the minimum required NUMA resources
req_numa_count=2
numa_count=$(lscpu | grep "NUMA node(s)" | awk '{print $3}')
if [ $numa_count -lt $req_numa_count ]; then
	exit 1
fi

# x86 systems typically support two threads per core while Power systems
# can support between two and eight threads per core.
threads_per_core=$(lscpu | grep "Thread(s) per core:" | awk '{print $4}')
# cores_per_socket=$(lscpu | grep "Core(s) per socket:" | awk '{print $4}')

# Calculate the number of CPUs required for the test.
let req_vcpu_count="2 * $threads_per_core"
let req_cpu_count="2 * $threads_per_core + $req_vcpu_count"

# Overall CPU allocation strategy for the VM:
# - Allocate two CPU cores. Threads on the first core will be evenly divided
#   between OS and DPDK application use.  Threads on the second core will be
#   used exclusively for PMD polling.
# Overall CPU allocation strategy for the host:
# - Reserve the first CPU core on each NUMA node for host OS use.  Select two
#   additional CPU cores, one for OVS/DPDK application usage and one for PMD
#   polling use.
# ToDo: Finish this description and implementation

# Identify the NUMA node associated with the given PCI device
# along with another NUMA node not associated with the device
dev_numa_node1=$(lspci  -s $dev_pci -v | grep -o "NUMA node [0-9]*" | awk '{print $3}')
dev_numa_node2=$(lscpu | grep "NUMA node.*CPU" | grep -v "NUMA node${dev_numa_node1}" | head -n 1 | sed -E 's/^NUMA node([0-9]*).*/\1/g')

# ToDo: Power systems have NUMA nodes without any associated CPUs. How to
#       identify them?

# Obtain a list of CPUs associated with each NUMA node,
parse_range $(lscpu | grep "NUMA node${dev_numa_node1}" | awk '{print $4}') numa_cpu_list1
parse_range $(lscpu | grep "NUMA node${dev_numa_node2}" | awk '{print $4}') numa_cpu_list2

# Create a list of CPU siblings for the first CPU of each NUMA node
# reserved for host OS use
num=$(echo $numa_cpu_list1 | awk -F, '{print $1}')
parse_range $(cat /sys/devices/system/cpu/cpu${num}/topology/thread_siblings_list) host_cpu_list1
for cpu in ${host_cpu_list1//,/ }; do
	numa_cpu_list1=$(echo $numa_cpu_list1 | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done

num=$(echo $numa_cpu_list2 | awk -F, '{print $1}')
parse_range $(cat /sys/devices/system/cpu/cpu${num}/topology/thread_siblings_list) host_cpu_list2
for cpu in ${host_cpu_list2//,/ }; do
	numa_cpu_list2=$(echo $numa_cpu_list2 | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done

# Save the list of CPUs to be islated from host OS use
dut_isolated_cpus=$numa_cpu_list1

# Count the number of DUT isolated CPUs and make sure there are enough
# to assign for all requirements
dut_isolated_cpus_count=$(echo $dut_isolated_cpus | awk -F, '{print NF}')
if [ $dut_isolated_cpus_count -lt $req_cpu_count ]; then
	exit 1
fi

remaining_dut_isolated_cpus=$dut_isolated_cpus

# Select CPUs for the OVS/DPDK application
num=$(echo $remaining_dut_isolated_cpus | awk -F, '{print $1}')
parse_range $(cat /sys/devices/system/cpu/cpu${num}/topology/thread_siblings_list) dut_app_cpus
for cpu in ${dut_app_cpus//,/ }; do
	remaining_dut_isolated_cpus=$(echo $remaining_dut_isolated_cpus | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done

# Select CPUs for the DPDK PMDs
num=$(echo $remaining_dut_isolated_cpus | awk -F, '{print $1}')
parse_range $(cat /sys/devices/system/cpu/cpu${num}/topology/thread_siblings_list) dut_pmd_cpus
for cpu in ${dut_pmd_cpus//,/ }; do
	remaining_dut_isolated_cpus=$(echo $remaining_dut_isolated_cpus | sed "s/^$cpu,//g" | sed "s/,$cpu,/,/g")
done

dut_isolated_cpus()
{
	local isolated_cpus=""
	compact_range $dut_isolated_cpus isolated_cpus
	echo $isolated_cpus
}

# Returns a mask of CPUs reserved for DPDK PMD use
dut_dpdk_pmd_mask()
{
	hex_string=""
	for cpu in ${dut_pmd_cpus//,/ }; do
		hex_string="${hex_string}1<<${cpu}|"
	done
	hex_string="${hex_string}0"
	echo `python3 -c "print(hex($hex_string))"`
}

dut_dpdk_lcore_mask()
{
	hex_string=""
	for cpu in ${dut_app_cpus//,/ }; do
		hex_string="${hex_string}1<<${cpu}|"
	done
	hex_string="${hex_string}0"
	echo `python3 -c "print(hex($hex_string))"`
}

dut_pmd_rxq_affinity()
{
	res=$(i=0; for t in ${dut_pmd_cpus//,/ }; do printf "${i}:${t},"; let i++; done | sed 's/,$//')
	echo $res
}

vcpu_count()
{
	echo $req_vcpu_count
}

vcpu_str()
{
	local vcpu_str=""
	res=$(i=1; for t in ${remaining_dut_isolated_cpus//,/ }; do printf "${t},"; if [ $i -ge $req_vcpu_count ]; then break; fi; let i++; done | sed 's/,$//')
	compact_range $res vcpu_str
	echo $vcpu_str
}

vcpu_0()
{
	echo $remaining_dut_isolated_cpus | awk -F, '{print $1}'
}

vcpu_1()
{
	echo $remaining_dut_isolated_cpus | awk -F, '{print $2}'
}

vcpu_2()
{
	echo $remaining_dut_isolated_cpus | awk -F, '{print $3}'
}

vcpu_3()
{
	echo $remaining_dut_isolated_cpus | awk -F, '{print $4}'
}

vcpu_4()
{
	if [ $threads_per_core -eq 4 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $5}'
	else
		exit 1
	fi
}

vcpu_5()
{
	if [ $threads_per_core -eq 4 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $6}'
	else
		exit 1
	fi
}

vcpu_6()
{
	if [ $threads_per_core -eq 4 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $7}'
	else
		exit 1
	fi
}

vcpu_7()
{
	if [ $threads_per_core -eq 4 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $8}'
	else
		exit 1
	fi
}

vcpu_emulator()
{
	# ToDo: What about other threads per core values?
	if [ $threads_per_core -eq 2 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $5}'
	elif [ $threads_per_core -eq 4 ]; then
		echo $remaining_dut_isolated_cpus | awk -F, '{print $9}'
	else
		exit 1
	fi
}

numa_node()
{
	echo $dev_numa_node1
}

driver_queues()
{
	echo $threads_per_core
}

$func_name
