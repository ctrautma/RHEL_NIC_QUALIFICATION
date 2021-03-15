#!/usr/bin/env python3
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   trex_sport.py for synergy test
#   Author: Hekai Wang <hewang@redhat.com>
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


import sys, getopt
sys.path.append('/opt/trex/current/automation/trex_control_plane/stl/examples')
sys.path.append('./v2.48/automation/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./v2.48/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./v2.49/automation/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./v2.49/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.49/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./current/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./current/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./current/automation/trex_control_plane/stf/trex_stf_lib/')

import stl_path
from trex_stl_lib.api import STLClient,STLStream,STLPktBuilder,STLFlowStats,STLTXCont,STLFlowLatencyStats
from trex_stl_lib.api import STLTXSingleBurst,STLVmFixIpv4,STLProfile,STLScVmRaw,STLVmFlowVar,STLVmWrFlowVar
from trex_client import TRexException
from scapy.layers.inet import IP, ICMP,TCP,UDP
from scapy.layers.l2 import Ether,Dot1Q,ARP
import json
import time
import argparse
print(sys.path)


def test_conn_ok(c,ports,streams):
    c.reset()

    c.set_port_attr(ports=ports,link_up=True)

    c.acquire(ports = ports, force = True)

    # add both streams to ports
    c.add_streams(streams, ports = ports)

    # clear the stats before injecting
    c.clear_stats()

    print("Start Test 10 Sec ")
    c.start(ports = ports, mult = "1kpps", duration = 10)
    c.wait_on_traffic(ports = ports)
    if c.get_warnings():
            print("Warning")

    stat = c.get_stats()
    print(json.dumps(stat,indent=4,sort_keys=False))
    port_index = ports[0]
    flow_tx_pkts = stat["flow_stats"][1]["tx_pkts"][port_index]
    flow_rx_pkts = stat["flow_stats"][1]["rx_pkts"][port_index]
    if flow_tx_pkts > 0 and flow_rx_pkts > 0 and flow_tx_pkts == flow_rx_pkts:
        return True
    else:
        return False


def repeat_through_put(c,rate,duration,ports,streams):
    c.reset()

    c.acquire(ports = ports, force = True)

    # add both streams to ports
    c.add_streams(streams, ports = ports)

    # clear the stats before injecting
    c.clear_stats()

    print("start %s percent throughput begin " % rate)

    c.start(ports = ports, mult = str(rate) + "%", duration = duration)

    c.wait_on_traffic(ports = ports)
    if c.get_warnings():
            print("Warning")

    return c.get_stats()

#Do not use this function
def start_trex_deamon(server_ip):
    trex = trex_client.CTRexClient(server_ip,trex_args="--no-ofed-check -w 10")
    print('Kill all running trex')
    trex.kill_all_trexes()
    time.sleep(5)
    for i in range(10):
        if trex.get_trex_cmds():
            break
        else:
            try:
                trex.start_stateless()
            except TRexException as e:
                print(e)
            time.sleep(3)
    print(trex.get_trex_cmds())
    trex_log = trex.get_trex_log()
    print(trex_log)
    if "Link Down" in trex_log:
        print("Start trex server Failed")
        return False
    else:
        print("Start trex server successful")
        return True

def create_throughput_test_profile(pkt_dst_mac,pkt_size):
    base_pkt = Ether(dst=pkt_dst_mac)/IP(src="192.168.100.10",
                                        dst="192.168.100.20")/UDP(dport=12, sport=1025)
    pad = max(0, pkt_size - len(base_pkt)) * 'x'

    base_stream = STLStream( isg = 10.0, # star in delay
            name = 'S1',
            packet = STLPktBuilder(pkt = base_pkt/pad),
            flow_stats = STLFlowStats(pg_id = 1 ),
            #flow_stats = None,
            #mode = STLTXSingleBurst( pps = 10, total_pkts = 10)
            #mode= STLTXCont(pps = 10000),
            mode = STLTXCont(percentage = 100)
            )

    all_stream = []
    noise_base_pkt = Ether(dst="ff:ff:ff:ff:ff:ff")/ARP(op=1)
    vm = STLScVmRaw( [ STLVmFlowVar ("ip_src",
                                    min_value="172.16.0.1",
                                    max_value="172.16.100.254",
                                    size=4,
                                    step=1,
                                    op="inc"),
                    STLVmWrFlowVar (fv_name="ip_src",
                                    pkt_offset= "ARP.psrc" ), # write ip to packet IP.src
                    STLVmFixIpv4(offset = "ARP")                                # fix checksum
                    ],
                    #split_by_field = "ip_src",
                    #cache_size =255 # cache the packets, much better performance
                )

    noise_pkt = STLPktBuilder(pkt = noise_base_pkt/pad,vm = vm)

    stream = STLStream( packet = noise_pkt, mode = STLTXSingleBurst( pps = 10, total_pkts = 300))
    
    all_stream.append(base_stream)
    all_stream.append(stream)

    s1 =  STLProfile(streams=all_stream).get_streams()
    return s1

if __name__ == "__main__":
    import trex_client
    import trex_status

    parser = argparse.ArgumentParser(description='Test hpe synergy test')
    parser.add_argument('-c','--connect',  type=str,help='trex server ip ',required=True)
    parser.add_argument('-m','--maxcycle', type=int,help='get no loss packets cycle times',required=False)
    parser.add_argument('-t','--time', type=int,help='one time test duration',required=False)
    parser.add_argument('-d','--dst_mac',type=str,help='make packet dst mac address',required=False)
    parser.add_argument('-s','--src_mac',type=str,help='make packet src mac address',required=False)
    parser.add_argument('--pkt_size',type=int,help='init packet size',required=False)
    parser.add_argument('--verify_time',type=int,help='how long time for last performance verify',required=False)
    parser.add_argument('--init_percent',type=str,help='init speed percent',required=False)
    args = parser.parse_args()
    print(args)
    store_file = args.store_file

    server_ip="10.73.130.211"
    pkt_size=64
    pkt_dst_mac="52:54:00:11:8F:E8"
    pkt_src_mac="52:54:00:11:8F:E8"

    if args.connect:
        server_ip=args.connect
    if args.dst_mac:
        pkt_dst_mac=args.dst_mac
    if args.src_mac:
        pkt_src_mac=args.src_mac
    if args.pkt_size:
        pkt_size=args.pkt_size

    if args.verify_time:
        verify_time=args.verify_time
    else:
        verify_time=600

    if args.init_percent:
        init_percent = int(args.init_percent)
    else:
        init_percent=100

    c = STLClient(server=server_ip)

    s1 = create_throughput_test_profile(pkt_dst_mac,pkt_size)

    c.connect()

    real_ports = []
    port_num = c.get_port_count()
    port_list = range(port_num)
    for i in range(port_num):
        ret = test_conn_ok(c,[i],s1)
        if ret == True:
            real_ports.append(i)
            break
        else:
            continue
    if len(real_ports) == 0:
        print("Invalid port")
        sys.exit(1)

    max_retry=1
    duration=10
    if args.maxcycle:
        max_retry=args.maxcycle
    if args.time:
        duration=args.time

    cur_max=init_percent
    cur_min=0
    try_vlaue=cur_max

    last_value=0
    last_result=""

    port_index = real_ports[0]

    # Set this as normal switch maybe loss packets while traffic jam .
    # IF you make sure to get 0 lose packet , set this value as 0
    # default_loss_percent = 2/10000
    default_loss_percent = 0

    for i in range(max_retry):
        print("current %s cycle repeat" % i)
        stat = repeat_through_put(c,try_vlaue,duration,real_ports,s1)
        print(json.dumps(stat,indent=4,sort_keys=False))
        tx_total = int(stat["flow_stats"][1]["tx_pkts"][port_index])
        rx_total = int(stat["flow_stats"][1]["rx_pkts"][port_index])
        if tx_total - tx_total * default_loss_percent > rx_total:
            cur_max = try_vlaue
            try_vlaue = (cur_min + cur_max)/(2 * 1.0)
        else:
            last_value=try_vlaue
            last_result=json.dumps(stat,indent=4, sort_keys=False)
            speed_mpps = stat["total"]["tx_pps"]/1e6
            if last_result:
                with open(store_file,"a") as fd:
                    fd.write(f"repeat time cycle {i} with speed {speed_mpps} mpps\n")
                    fd.write(str(last_result))
                    fd.write("\n")
            #Get the full speed of the test nic card, So break
            if try_vlaue == cur_max:
                break
            cur_min = try_vlaue
            try_vlaue = (cur_min + cur_max)/(2 * 1.0)

    print("begine long time test begin %s percent " % (last_value))
    default_loss_percent = 2/10000
    stat = repeat_through_put(c,last_value/2,verify_time,real_ports,s1)
    print(json.dumps(stat,indent=4,sort_keys=False))
    all_tx_packets = int(stat["flow_stats"][1]["tx_pkts"][port_index])
    all_rx_packets = int(stat["flow_stats"][1]["rx_pkts"][port_index])
    if all_tx_packets - all_tx_packets * default_loss_percent > all_rx_packets:
        last_value = 0
    else:
        pass
    last_result=json.dumps(stat,indent=4, sort_keys=False)
    last_speed_mpps = int(stat["total"]["tx_pps"])*2/1e6
    print("begine long time test end")
    print("************************************************")
    if(0 == last_value):
        print("long time test find lose packets !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    print("last result is",last_speed_mpps,"mpps")
    print(last_result)
    print("************************************************")

    c.disconnect()
    import sys
    if 0 == last_value:
        sys.exit(3)
    else:
        sys.exit(0)
