# helper for SR-IOV

# create VFs for PF
#
# *** NOTE:
# sriov_create_vfs() must be called before any VF is attached to VM
# becasue for some kind of NIC, to create new VF, the driver must be unloaded, therefore
# the created VF will be remvoed and this could incur issue
[ -e ./lib_mlx.sh ] && source ./lib_mlx.sh
[ -e ./lib_chelsio.sh ] && source ./lib_chelsio.sh
[ -e ./lib_nfp.sh ] && source ./lib_nfp.sh

sriov_create_vfs()
{
	local PF=$1
	local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
	local num_vfs=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	ip link set $PF up

	echo ----------------------
	lspci | grep -i ether
	echo ----------------------
	case ${driver} in
		mlx4_en)
			if [ -e lib_mlx.sh ];then
				mlx_create_vfs $@
			else
				echo "no lib for mellanox"
				return 1
			fi
			;;
		cxgb4)
			if [ -e lib_chelsio.sh ];then
				chelsio_create_vfs $@
			else
				echo "no lib for chelsio"
				return 1
			fi
			;;
		mlx5_core)
                        if [ -e lib_mlx.sh ];then
                                mlx_create_vfs $@
                        else
                                echo "no lib for mellanox"
                                return 1
                        fi
			;;
		*)
			echo ${num_vfs} > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
		        sleep 5

       			lspci | grep -i ether
        		echo ----------------------

        		if (( $(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | wc -l) != ${num_vfs} )); then
                		echo "FAIL to create VFs"
                		return 1
        		fi

        		ip link set $PF up
        		ip link show $PF
			;;
	esac
	link_up_ifs_with_same_bus $pf_bus_info
}

# remove VFs for PF
sriov_remove_vfs()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	echo ----------------------
	lspci | grep -i ether
	echo ----------------------
	case ${driver} in
		mlx4_en)
			mlx_remove_vfs $@
			;;
		cxgb4)
			chelsio_remove_vfs $@
			;;
                mlx5_core)
			mlx_remove_vfs $@
                        ;;

		*)
			echo 0 > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
		        sleep 5

        		lspci | grep -i ether
        		echo ----------------------

        		if (($(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* 2>/dev/null | wc -l) != 0)); then
                		echo "FAIL to remove VFs"
                		return 1
        		fi

        		ip link set $PF down
        		sleep 2
        		ip link set $PF up
        		ip link show $PF
			;;
	esac
}

# attach VF to VM, one for each calling
sriov_attach_vf_to_vm()
{
	local PF=$1
	local iPF=$2 # start from 0.
	             # For cxgb4, PF used to create VF is different from the original PF
	local iVF=$3 # index of vf, starting from 1
	local vm=$4
	local mac=$5
	local vlan=$6

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	link_up_ifs_with_same_bus $pf_bus_info

	case ${driver} in
		cxgb4)
			chelsio_attach_vf_to_vm $@
			return $?
			;;
	esac

	local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
	local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')
	local domain=$(echo $vf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $vf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $vf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $vf_bus_info | awk -F '[:|.]' '{print $4}')

	if [ "$SRIOV_USE_HOSTDEV" = "yes" ]; then
		ip link set $PF vf $(($iVF-1)) mac $mac
		cat <<-EOF > ${vf_nodedev}.xml
			<hostdev mode='subsystem' type='pci' managed='yes'>
				<source>
					<address domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
				</source>
			</hostdev>
		EOF
	else
		if [ -n "$vlan" ]; then
			cat <<-EOF > ${vf_nodedev}.xml
				<interface type='hostdev' managed='yes'>
					<source>
						<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
					</source>
					<mac address='${mac}'/>
					<vlan>
						<tag id='${vlan}'/>
					</vlan>
				</interface>
			EOF
		else
			# workaround for bz1215975
			if [ $(ethtool -i $PF | grep 'driver:' | awk '{print $2}') = 'qlcnic' ]; then
				cat <<- EOF > ${vf_nodedev}.xml
					<interface type='hostdev' managed='yes'>
						<source>
							<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
						</source>
						<mac address='${mac}'/>
							<vlan>
								<tag id='4095'/>
							</vlan>
					</interface>
				EOF
			else
				cat <<- EOF > ${vf_nodedev}.xml
					<interface type='hostdev' managed='yes'>
						<source>
							<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
						</source>
						<mac address='${mac}'/>
					</interface>
				EOF
			fi
		fi
	fi

	if virsh attach-device $vm ${vf_nodedev}.xml; then
		sleep 5
		if [ $driver = "cxgb4" ];then
			local cmd=(
                                {export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
                                {echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/accept_dad}
                                {echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/dad_transmits}
                        )
                        vmsh cmd_set $vm "${cmd[*]}"
		fi
		return 0
	fi
	return 1
}

# detach VF from VM, one for each calling
sriov_detach_vf_from_vm()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of vf, starting from 1
	local vm=$4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			mlx_detach_vf_from_vm $@
			return $?
			;;
		cxgb4)
			chelsio_detach_vf_from_vm $@
			return $?
			;;
		*)
			local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
        		local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')

        		if virsh detach-device $vm ${vf_nodedev}.xml; then
                		sleep 5
        		fi
			;;
	esac
}

sriov_attach_pf_to_vm()
{
	local PF=$1
	local vm=$2

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')
        local pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')

	link_up_ifs_with_same_bus $pf_bus_info

	local domain=$(echo $pf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $pf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $pf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $pf_bus_info | awk -F '[:|.]' '{print $4}')

	cat <<-EOF > ${pf_nodedev}.xml
		<hostdev mode='subsystem' type='pci' managed='yes'>
			<source>
				<address domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
			</source>
		</hostdev>
	EOF
		
	if virsh attach-device $vm ${pf_nodedev}.xml; then
		return 0
	fi
	return 1
}

sriov_detach_pf_from_vm()
{
	local pf_bus_info=$1
	local vm=$2

        local pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')
	local domain=$(echo $pf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $pf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $pf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $pf_bus_info | awk -F '[:|.]' '{print $4}')

        if virsh detach-device $vm ${pf_nodedev}.xml; then
            		sleep 5
        fi
}

# get vf interface
sriov_get_vf_iface()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			echo $(mlx_get_vf_iface $@)
			;;
		cxgb4)
			echo $(chelsio_get_vf_iface $@)
			;;
		*)
			local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)

        		local vf_iface=()
        		local cx=0
       			while [ -z "$vf_iface" ] && (($cx < 60)); do
                		sleep 1

                		vf_iface=($(ls /sys/bus/pci/devices/${vf_bus_info}/net 2>/dev/null))
                		let cx=cx+1
        		done

		        echo ${vf_iface[0]}
			;;
	esac
}

# check if vf mac is 00:00:00:00:00:00
sriov_vfmac_is_zero()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1


	local vf_iface=$(sriov_get_vf_iface $PF $iPF $iVF)

	local vfmac=$(cat /sys/class/net/${vf_iface}/address)
	if [ "$vfmac" = "00:00:00:00:00:00" ]; then
		return 0
	fi

	return 1
}

sriov_get_vf_bus_info()
{
      local PF=$1
      local iPF=$2
      local iVF=$3

      local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
      local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

      case ${driver} in
                mlx4_en)
			local vf_bus_info=$(mlx_get_vf_bus_info $@)
			rtn=$?
			echo ${vf_bus_info}
                        return $rtn
                        ;;
                cxgb4)
			local vf_bus_info=$(chelsio_get_vf_bus_info $@)
                        rtn=$?
                        echo ${vf_bus_info}
                        return $rtn
                        ;;
		*)
     			local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
     			rtn=$?
      	     		echo ${vf_bus_info}
	     		return $rtn
		        ;;
      esac
}

sriov_get_pf_bus_info()
{
      local PF=$1
      local iPF=$2

      local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
      local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

      case ${driver} in
                mlx4_en)
			pf_bus_info=$(mlx_get_pf_bus_info $@)
			echo $pf_bus_info
                        ;;
                cxgb4)
			pf_bus_info=$(chelsio_get_pf_bus_info $@)
			echo $pf_bus_info
                        ;; 
		*)
			echo $pf_bus_info
		        ;;
      esac
}

get_all_ifs_with_same_bus()
{
	bus=$1
	result=""

	for ifname in $(ip link | grep "mtu" | awk '{ print $2 }' | sed 's/://g')
	do
		if [ "$ifname" = "lo" ];then
			continue
		fi
        	bus_info=$(ethtool -i $ifname|grep bus-info|awk -F" " '{print $2}')
        	if [ "$bus" = "$bus_info" ];then
                	result+=" $ifname"
        	fi
	done

	echo $result
}

link_up_ifs_with_same_bus()
{
	bus=$1
	dual_ports=$(get_all_ifs_with_same_bus $bus)
	for port in $dual_ports
	do
		ip link set $port up
	done
}

vm_netperf_ipv4()
{
        local vm=$1
        local ipv4=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -L "$1 } else { print $1 } }')
        local p_ipv4=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -I "$1 } else { print $1 } }')

        local log=""

        # IPv4
        vmsh run_cmd $vm "timeout 120s bash -c \"until ping -c3 $p_ipv4; do sleep 10; done\"" > /tmp/perf.log
        if [ $? -eq 0 ];then
                vmsh run_cmd $vm "netperf -4 -t UDP_STREAM -H $ipv4 -l 30 -- -m 10000" > /tmp/perf.log
                if (( $? )); then
                        UDP_STREAMv4=0
                else
                        UDP_STREAMv4=$(cat /tmp/perf.log|sed -n '/netperf/,/^\[root@.*]#/ {/.*/ p}'|sed -n '/\(\b[0-9]\+\)\{5,\}/ p'|sed 's/[\r\n]//'|tail -n1|awk '{printf $NF}')
                fi
        fi

        echo $UDP_STREAMv4
}

vm_netperf_ipv6()
{
        local vm=$1
        local ipv6=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -L "$1 } else { print $1 } }')
        local p_ipv6=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -I "$1 } else { print $1 } }')

        local log=""

        # IPv4
        vmsh run_cmd $vm "timeout 120s bash -c \"until ping6 -c3 $p_ipv6; do sleep 10; done\"" > /tmp/perf.log
        if [ $? -eq 0 ];then
                vmsh run_cmd $vm "netperf -6 -t UDP_STREAM -H $ipv6 -l 30 -- -m 10000" > /tmp/perf.log
                if (( $? )); then
                        UDP_STREAMv6=0
                else
                        UDP_STREAMv6=$(cat /tmp/perf.log|sed -n '/netperf/,/^\[root@.*]#/ {/.*/ p}'|sed -n '/\(\b[0-9]\+\)\{5,\}/ p'|sed 's/[\r\n]//'|tail -n1|awk '{printf $NF}')
                fi
        fi
        echo $UDP_STREAMv6
}

