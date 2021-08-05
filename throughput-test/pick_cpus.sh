#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   pick_cpus.sh
#   Author: Zhiqiang Fang <zfang@redhat.com>
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

# Usage:
# Before run this script please define "dut_interface_1_pciid" in Perf-Verify.conf which is needed here.

. get_cpu_numbers.sh
. Perf-Verify.conf

nicnumanode=$(nic_numa_node ${dut_interface_1_pciid})
nicnumanode_cpu_list=($(cpus_on_numa $nicnumanode))

IFS=$'\n' sorted_nicnumanode_cpu_list=($(sort -n <<<"${nicnumanode_cpu_list[*]}"))
unset IFS
#printf "[%s]\n" "${sorted_nicnumanode_cpu_list[@]}"
#echo ${sorted_nicnumanode_cpu_list[@]}

#PMD_CPU_1 use the first cpu (cpu 0 was removed from the list)
echo "PMD_CPU_1 is ${sorted_nicnumanode_cpu_list[0]}"

#PMD_CPU_2 use the paired thread within first CPU
echo "PMD_CPU_2 is $(sibling ${sorted_nicnumanode_cpu_list[0]})"

#PMD_CPU_3 use the second cpu
echo "PMD_CPU_3 is ${sorted_nicnumanode_cpu_list[1]}"
echo "PMD_CPU_4 is $(sibling ${sorted_nicnumanode_cpu_list[1]})"

echo "VCPU1 is $(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-1]})"
echo "VCPU2 is ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-1]}"
echo "VCPU3 is $(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-2]})"
echo "VCPU4 is $(sibling ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-3]})"
echo "VCPU5 is ${sorted_nicnumanode_cpu_list[${#nicnumanode_cpu_list[@]}-3]}"
