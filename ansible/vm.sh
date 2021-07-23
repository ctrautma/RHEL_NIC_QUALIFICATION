#!/usr/bin/expect

#
# A tool to use 'virsh console'
# to run cmdline on a VM
# and return the exit code
#
# e.g.
#
# 1. run a single command
#    vmsh run_cmd guest_name "ifconfig"
# 
# 2. run a set of commands
# #!/bin/bash
#
# cmd=(
#     {ifconfig}
#     {date}
#     {ip link show}
# )
# vmsh cmd_set guest_name "${cmd[*]}"
#

# expect timeout
if { [catch {set VMSH_TIMEOUT $::env(VMSH_TIMEOUT)}] } { set VMSH_TIMEOUT "3600" }
set timeout $VMSH_TIMEOUT 

# command line prompt
if { [catch {set VMSH_PROMPT $::env(VMSH_PROMPT)}] } { set VMSH_PROMPT {\[root@(\S+) .+\]\# } }
if { [catch {set VMSH_PROMPT1 $::env(VMSH_PROMPT1)}] } { set VMSH_PROMPT1 $VMSH_PROMPT }

# user name and password used to login guest
if { [catch {set VM_USERNAME $::env(VM_USERNAME)}] } { set VM_USERNAME "root" }
if { [catch {set VM_PASSWORD $::env(VM_PASSWORD)}] } { set VM_PASSWORD "root" }

# var to control if checking cmdline result
if { [catch {set VMSH_NORESULT $::env(VMSH_NORESULT)}] } { set VMSH_NORESULT 0 }

# var to control if logout after running vmsh run_cmd
if { [catch {set VMSH_NOLOGOUT $::env(VMSH_NOLOGOUT)}] } { set VMSH_NOLOGOUT 0 }

# exit_code is exit code when running the required command
# it'll be saved in $? for bash
set exit_code 0

##########################################################################

set sid -1
set ssh_sid -1

proc login_vm { name } {
        global VM_USERNAME
        global VM_PASSWORD
        global VMSH_PROMPT
        global VMSH_PROMPT1
        global sid

        spawn virsh console $name
        expect {
                "Escape character is \^]" { sleep 1; send "\r" }
                timeout {
                        puts "FAIL: timeout to login vm \"$name\"!"
                        exit 1
                }
        }
        expect {
                "Last login:" { exp_continue }
                "login: " { send "$VM_USERNAME\r"; exp_continue }
                "Password:" { send "$VM_PASSWORD\r"; exp_continue }
                -re $VMSH_PROMPT { }
                -re $VMSH_PROMPT1 { }
                "Login incorrect" { puts "FAIL:  Incorrect to login vm \"$name\"!"; exit 1 }
                "error:" { exit 1 }
                timeout {
                        puts "FAIL: timeout to login vm \"$name\"!"
                        exit 1
                }
        }

        set sid $spawn_id
}


proc ssh_login_vm { vm_ip } {
	global VM_USERNAME
	global VM_PASSWORD
	global VMSH_PROMPT
	global VMSH_PROMPT1
	global ssh_sid

	spawn ssh root@$vm_ip
	expect {
		"yes/no" { send "yes\r"; exp_continue }
		"*password:" { send "$VM_PASSWORD\r"; exp_continue }
		-re $VMSH_PROMPT { }
		-re $VMSH_PROMPT1 { }
		"Login incorrect" { puts "FAIL:  Incorrect to login vm \"$vm_ip\"!"; exit 1 }
		"error:" { exit 1 }
		timeout {
			puts "FAIL: timeout to login vm \"$vm_ip\"!"
			exit 1
		}
	}

	set ssh_sid $spawn_id
}

proc logout_vm { } {
        global VMSH_NOLOGOUT
        global sid

        if { $VMSH_NOLOGOUT == 0 } {
                send -i $sid "logout\r"
                expect {
                        -i $sid
                        "login: " { }
                        timeout { puts "TIMEOUT to logout" }
                }
        }

        send -i $sid "\035"
        sleep 1
}

proc ssh_logout_vm { } {
        global VMSH_NOLOGOUT
        global ssh_sid

        if { $VMSH_NOLOGOUT == 0 } {
                send -i $ssh_sid "logout\r"
                expect {
                        -i $ssh_sid
                        "*closed." { }
                        timeout { puts "TIMEOUT to logout" }
                }
        }

        send -i $ssh_sid "\035"
        sleep 1
}


proc send_vm_ip_to_target { vm_name target_ip target_passwd } {
        global sid
	global exit_code
	global VMSH_PROMPT
        global VMSH_PROMPT1
        global VMSH_NORESULT

        login_vm $vm_name

        send -i $sid "export local_ip=\$(ip addr|grep \"inet \"|grep -v \"127.0.0.1\"|awk '{print \$2}'| awk -F/ '{print \$1}')\r"
	expect * 
	send -i $sid "echo \$local_ip > /home/local_ip\r"

	send -i $sid "scp /home/local_ip root@$target_ip:/home/vmip\r"
	expect {
		-i $sid
		"*(yes/no)?" { send -i $sid "yes\n";exp_continue }
		"*password:" { send -i $sid "$target_passwd\n" }
	}

	sleep 1

        logout_vm
}

proc change_local_passwd { passwd } {
	spawn passwd
	expect {
		"New password:" { send  "$passwd\n"; exp_continue }
		"Retype new password:" { send "$passwd\n"; exp_continue }
		"successfully" {}
	}
}

#
# run a single command
#
# e.g.
# ./vmsh run_cmd guest_name "ifconfig"
#
# exit code when running the command is saved in $? for bash
#
proc run_cmd { name cmd } {
	global sid
	global exit_code
	global VMSH_PROMPT
	global VMSH_PROMPT1
	global VMSH_NORESULT

	login_vm $name

	send -i $sid "$cmd\r"

	if { $VMSH_NORESULT == 0 } {
		expect {
			-i $sid
			-re $VMSH_PROMPT { }
			-re $VMSH_PROMPT1 { }
			timeout {
				puts "FAIL(1):TIMEOUT to run_cmd \"$cmd\""
				exit 1
			}
		}

		expect *
		send -i $sid "echo \$?\r"
		expect {
			-i $sid
			-re "\n(\\d+)\r" { set exit_code  $expect_out(1,string) }
			-re $VMSH_PROMPT { send -i $sid "echo \$?\r"; exp_continue }
			-re $VMSH_PROMPT1 { send -i $sid "echo \$?\r"; exp_continue }
			timeout {
				puts "FAIL(2):TIMEOUT to run_cmd \"$cmd\""
				set exit_code 1
			}
		}
		expect {
			-i $sid
			-re $VMSH_PROMPT { }
			-re $VMSH_PROMPT1 { }
			timeout {
				puts "FAIL(3):TIMEOUT to run_cmd \"$cmd\""
				exit 1
			}
		}
	} else {
		expect {
			-i $sid
			"\r" { sleep 2 }
			timeout {}
		}
	}

	logout_vm
}

proc ssh_run_cmd { vm_ip cmd } {
        global ssh_sid
        global exit_code
        global VMSH_PROMPT
        global VMSH_PROMPT1
        global VMSH_NORESULT

        ssh_login_vm $vm_ip

        send -i $ssh_sid "$cmd\r"

        if { $VMSH_NORESULT == 0 } {
                expect {
                        -i $ssh_sid
                        -re $VMSH_PROMPT { }
                        -re $VMSH_PROMPT1 { }
                        timeout {
                                puts "TIMEOUT to run_cmd \"$cmd\""
                                exit 1
                        }
                }

                expect *
                send -i $ssh_sid "echo \$?\r"
                expect {
                        -i $ssh_sid
                        -re "\n(\\d+)\r" { set exit_code  $expect_out(1,string) }
                        timeout {
                                puts "TIMEOUT to run_cmd \"$cmd\""
                                set exit_code 1
                        }
                }
                expect {
                        -i $ssh_sid
                        -re $VMSH_PROMPT { }
                        -re $VMSH_PROMPT1 { }
                        timeout {
                                puts "TIMEOUT to run_cmd \"$cmd\""
                                exit 1
                        }
                }
        } else {
                expect {
                        -i $ssh_sid
                        "\r" { sleep 2 }
                        timeout {}
                }
        }

        ssh_logout_vm
}

#
# run set of commands
# e.g.
#
# #!/bin/bash
#
# cmd=(
#     {ifconfig}
#     {date}
#     {ip link show}
# )
# ./vmsh cmd_set guest_name "${cmd[*]}"
#
# stop once fail to run a command
# and exit code saved in $? for bash
#
proc cmd_set { name cmd } {
	global sid
	global exit_code
	global VMSH_PROMPT
	global VMSH_PROMPT1

	login_vm $name

	foreach c $cmd {
		set result 0
		send -i $sid "$c\r"
		expect {
			-i $sid
			-re $VMSH_PROMPT { }
			-re $VMSH_PROMPT1 { }
			timeout {
				puts "FAIL(1):TIMEOUT to run_cmd \"$cmd\""
				exit 1
			}
		}

		expect *
		send -i $sid "echo \$?\r"
		expect {
			-i $sid
			-re "\n(\\d+)\r" { set result  $expect_out(1,string) }
			-re $VMSH_PROMPT { send -i $sid "echo \$?\r"; exp_continue }
			-re $VMSH_PROMPT1 { send -i $sid "echo \$?\r"; exp_continue }
			timeout {
				puts "FAIL(2):TIMEOUT to cmd_set \"$c\""
				set result 1
			}
		}
		expect {
			-i $sid
			-re $VMSH_PROMPT { }
			-re $VMSH_PROMPT1 { }
			timeout {
				puts "FAIL(3):TIMEOUT to cmd_set \"$c\""
				exit 1
			}
		}
		set exit_code [expr {$exit_code + $result}]
	}

	logout_vm
}

proc ssh_cmd_set { vm_ip cmd } {
        global ssh_sid
        global exit_code
        global VMSH_PROMPT
        global VMSH_PROMPT1

        ssh_login_vm $vm_ip

        foreach c $cmd {
                set result 0
                send -i $ssh_sid "$c\r"
                expect {
                        -i $ssh_sid
                        -re $VMSH_PROMPT { }
                        -re $VMSH_PROMPT1 { }
                        timeout {
                                puts "TIMEOUT to run_cmd \"$cmd\""
                                exit 1
                        }
                }

                expect *
                send -i $ssh_sid "echo \$?\r"
                expect {
                        -i $ssh_sid
                        -re "\n(\\d+)\r" { set result  $expect_out(1,string) }
                        timeout {
                                puts "TIMEOUT to cmd_set \"$c\""
                                set result 1
                        }
                }
                expect {
                        -i $ssh_sid
                        -re $VMSH_PROMPT { }
                        -re $VMSH_PROMPT1 { }
                        timeout {
                                puts "TIMEOUT to cmd_set \"$c\""
                                exit 1
                        }
                }
                set exit_code [expr {$exit_code + $result}]
        }

        ssh_logout_vm
}


##########################################################################
# main
#

set ret [eval $argv]
puts stdout $ret
exit $exit_code
