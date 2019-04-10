#!/bin/bash - 

if [[ ! ${NETWORK_COMMONLIB_DIR+x} ]]
then

	i_am_server() {
	    echo $SERVERS | grep -q $HOSTNAME
	}
	
	i_am_client() {
	    echo $CLIENTS | grep -q $HOSTNAME
	}
	
	i_am_standalone() {
	    echo $STANDALONE | grep -q $HOSTNAME
	}
	
	rhts_submit_log()
	{
		echo :: $FUNCNAME $@
	}

	# get NIC(s) for test by NIC_NUM and NIC_TEST
	get_required_iface()
	{
		local nic_test=($NIC_TEST)
	
		if ((${#nic_test[@]} < NIC_NUM))
		then
			echo "FAIL to get the needed interface(s) in $FUNCNAME"
			return 1
		fi
	
		local nic_list=""
		local i=0
		for ((i=0; i<NIC_NUM; i++))
		do
			[ -z "$nic_list" ] && nic_list="${nic_test[$i]}" || nic_list="${nic_list} ${nic_test[$i]}"
		done
	
		echo $nic_list
	}
fi

my_run_test()
{
	local my_test=$1
	local options=$2

	# skip tests under debugging
	if echo $my_test | grep -e "^_ovs_test" > /dev/null; then
		echo "SKIP_TEST $my_test!"
		return 0
	fi

	if [ -n "$OVS_SKIP" ] && echo $OVS_SKIP | grep -q -E "$my_test\b"; then
		echo "SKIP_TEST $my_test!"
	elif [ -z "$OVS_TOPO" ] || echo $OVS_TOPO | grep -q -E "(ovs_all|$my_test\b)"; then
		# is openvswitch version expected?
		if echo $options | grep -q ovs_version
		then
			local v1=$(rpm -q openvswitch | sed -e 's/openvswitch-\(.*\)-.*/\1/' | sed 's/ //g')
			local v2=$(expr "$options" : '.*ovs_version[><=!]*\([^,]*\)' | sed 's/ //g')
			local oo=$(expr "$options" : '.*ovs_version *\([><=!]*\)')

			v1=($(echo $v1 | sed 's/\./ /g'))
			v2=($(echo $v2 | sed 's/\./ /g'))

			local will_run=1
			for ((i=0; i<${#v1[@]}; i++))
			do
				if (($(bc <<< "${v1[$i]} != ${v2[$i]}")))
				then
					(($(bc <<< "${v1[$i]} $oo ${v2[$i]}"))) || ((will_run=0))
					break
				fi
			done
			((will_run)) || { echo "SKIP_TEST $my_test by unexpected openvswitch version"; return 0; }
		fi

		rlPhaseStartTest "$my_test"
		rlRun "$my_test"
		sleep 5

		# is jumbo_frame_test needed?
		if ! echo $options | grep -q jumbo_test || [[ $(expr "$options" : '.*jumbo_test *= *\([^,]*\)') =~ [yY].* ]]
		then
			rlRun "$my_test 9000"
		fi

		sleep 5
		rlPhaseEnd
	fi
}

