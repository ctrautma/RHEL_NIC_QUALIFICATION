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
