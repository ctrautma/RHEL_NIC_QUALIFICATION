#!/bin/sh
# lib_sync.sh

nc_log=/tmp/lib_nc_sync.log

lsof -v 2>/dev/null || yum -y install lsof

# helper for sync between multi-hosts

# ex.
# sync_set server "abc" 300
# sync_set client "abc" 300
# sync_set "hp-dl380pg8-08.rhts.eng.nay.redhat.com hp-dl380pg8-15.rhts.eng.nay.redhat.com" "abc" 300
sync_set()
{
	local xtrace_state="no"
	
    # Disable tracing if it is enabled to avoid excessive output to log file
    if [ -o xtrace ]; then xtrace_state="yes" && set +x; fi
    
	local peer=$1
	local state=$2
	local timeout=${3:-7200}
	local hn=$(hostname)
	local result=0

	echo "SYNC_NC: sync_set $@" | tee -a $nc_log

	case "$peer" in
		"server" | "SERVER") peer=($(echo $SERVERS));;
		"client" | "CLIENT") peer=($(echo $CLIENTS));;
		*) peer=($peer)
	esac

	while (($timeout > 0)) && ((${#peer[*]} > 0)); do
		for p in $(echo ${peer[@]}); do
			if echo "$state@$hn" | ncat $p 54321 2>>$nc_log; then
				echo "SYNC_NC: sent \"$state\" to $p" | tee -a $nc_log
				peer=($(echo ${peer[@]#$p}))
			fi
			sleep 1
		done

		let timeout=timeout-1
	done

	((timeout <= 0)) && (result=1; echo "SYNC_NC: timeout to \"sync_set $@\"")

	# Re-enable tracing if it had been set previously
    [[ "$xtrace_state" == "yes" ]] && set -x

	return $result
}

function sync_cleanup()
{
	while lsof -i TCP:54321 >>$nc_log; do
		local pid=$(lsof -i TCP:54321 | tail -n1 | awk '{print $2}')
		echo $pid | grep -e "\b[0-9]\+\b" >/dev/null && kill -9 $pid && wait $pid 2>>$nc_log
		sleep 1
	done

	[ -e $tmp ] && rm -rf $tmp

	return 0
}

function sync_ctrl_c()
{
	sync_cleanup
	exit 0
}

# ex.
# sync_wait server "abc" 300
# sync_wait client "abc" 300
# sync_wait "hp-dl380pg8-08.rhts.eng.nay.redhat.com hp-dl380pg8-15.rhts.eng.nay.redhat.com" "abc" 300
sync_wait()
{
	local xtrace_state="no"
	
    # Disable tracing if it is enabled to avoid excessive output to log file
    if [ -o xtrace ]; then xtrace_state="yes" && set +x; fi
    
	local peer=$1
	local state=${2:-""}
	local timeout=${3:-7200}
	local result=0

	echo "SYNC_NC: sync_wait $@" | tee -a $nc_log

	case "$peer" in
		"server" | "SERVER") peer=($(echo $SERVERS));;
		"client" | "CLIENT") peer=($(echo $CLIENTS));;
		*) peer=($peer)
	esac

	let timeout=timeout*1000000

	trap "sync_ctrl_c" SIGINT SIGQUIT SIGTERM

	tmp=$(mktemp)
	ncat -l 54321 -k > $tmp &
	echo "SYNC_NC: waiting \"${peer[@]}\"" | tee -a $nc_log

	{
		while [ -e $tmp ] && (($timeout > 0)) && ((${#peer[*]} > 0)); do
			if read -r line; then
				local s=$(echo $line | awk -F '@' '{print $1}')
				local h=$(echo $line | awk -F '@' '{print $2}')
				echo "SYNC_NC: got \"$s\" from $h" | tee -a $nc_log
				peer=($(echo ${peer[@]#$h}))
				((${#peer[*]} > 0)) && echo "SYNC_NC: waiting \"${peer[@]}\"" | tee -a $nc_log
			fi
			#usleep 100
			sleep 0.0001
			let timeout=timeout-100
		done
	} < $tmp

	((timeout <= 0)) && (result=1; echo "SYNC_NC: timeout to \"sync_wait $@\"")

	sync_cleanup
	
	# Re-enable tracing if it had been set previously
    [[ "$xtrace_state" == "yes" ]] && set -x

	return $result
}

# This function could be used when local system need the remote system to do a choice from 2 options.
# such as, the server whould do some checking before start test, if the checking pass, then it could 
# tell client to begin test, else tell the client the test should not start.
# ex.
# sync_wait_choice server "yes" "no" 300
# sync_wait_choice client "yes" "no" 300
# sync_wait_choice "hp-dl380pg8-08.rhts.eng.nay.redhat.com hp-dl380pg8-15.rhts.eng.nay.redhat.com" "yes" "no" 300
sync_wait_choice()
{
	local xtrace_state="no"
	
    # Disable tracing if it is enabled to avoid excessive output to log file
    if [ -o xtrace ]; then xtrace_state="yes" && set +x; fi
    
	local peer=$1
	local opt_yes=${2:-"yes"}
	local opt_no=${3:-"no"}
	local timeout=${4:-7200}
	local result=0

	echo "SYNC_NC: sync_wait $@" | tee -a $nc_log

	case "$peer" in
		"server" | "SERVER") peer=($(echo $SERVERS));;
		"client" | "CLIENT") peer=($(echo $CLIENTS));;
		*) peer=($peer)
	esac

	let timeout=timeout*1000000

	trap "sync_ctrl_c" SIGINT SIGQUIT SIGTERM

	tmp=$(mktemp)
	ncat -l 54321 -k > $tmp &
	echo "SYNC_NC: waiting \"${peer[@]}\"" | tee -a $nc_log

	{
		while [ -e $tmp ] && (($timeout > 0)) && ((${#peer[*]} > 0)); do
			if read -r line; then
				local s=$(echo $line | awk -F '@' '{print $1}')
				local h=$(echo $line | awk -F '@' '{print $2}')
				if [ "$s" == "$opt_no" ];then
					echo "SYNC_NC: got \"$s\" from $h" | tee -a $nc_log
					let result++
					peer=($(echo ${peer[@]#$h}))
				elif [ "$s" == "$opt_yes" ];then
					echo "SYNC_NC: got \"$s\" from $h" | tee -a $nc_log
					peer=($(echo ${peer[@]#$h}))
				else
					echo " SYNC_NC: warn, got a unexpected option $s from $h"
				fi
				((${#peer[*]} > 0)) && echo "SYNC_NC: wait_choice \"${peer[@]}\"" | tee -a $nc_log
			fi
			#usleep 100
			sleep 0.0001
			let timeout=timeout-100
		done
	} < $tmp

	((timeout <= 0)) && (result=1; echo "SYNC_NC: timeout to \"sync_wait_choice $@\"")

	sync_cleanup
	
	# Re-enable tracing if it had been set previously
    [[ "$xtrace_state" == "yes" ]] && set -x

	return $result
}

