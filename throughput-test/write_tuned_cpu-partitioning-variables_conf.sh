#!/bin/bash
. Perf-Verify.conf
echo "isolated_cores=$PMD_CPU_1,$PMD_CPU_2,$PMD_CPU_3,$PMD_CPU_4,$VCPU1,$VCPU2,$VCPU3,$VCPU4,$VCPU5" >> /etc/tuned/cpu-partitioning-variables.conf
