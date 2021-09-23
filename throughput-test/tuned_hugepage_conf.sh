#!/bin/bash

pushd /root/RHEL_NIC_QUALIFICATION/throughput-test

. Perf-Verify.conf

grubby --args='intel_iommu=on iommu=pt default_hugepagesz=1G hugepagesz=1G hugepages=32' --update-kernel=$(grubby --default-kernel)
echo "isolated_cores=$PMD_CPU_1,$PMD_CPU_2,$PMD_CPU_3,$PMD_CPU_4,$VCPU1,$VCPU2,$VCPU3,$VCPU4,$VCPU5" >> /etc/tuned/cpu-partitioning-variables.conf
tuned-adm profile cpu-partitioning
systemctl enable tuned

