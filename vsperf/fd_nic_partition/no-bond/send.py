import sys
sys.path.append('/tmp/v2.36/automation/trex_control_plane/stl')
sys.path.append('/tmp/v2.36/stl')
#import stl_path
from trex_stl_lib.api import *
import json
from udp_1pkt_vxlan import *

#base = Ether(dst="52:54:00:11:8f:ea",src="90:e2:ba:90:d9:34")/IP(src="16.0.0.1",dst="48.0.100.2")/UDP(dport=1234,sport=1234,chksum=None)
#base.show()
#help(UDP)
#sys.exit()

def stateless():
    try:
        # connect to server
        c = STLClient(server=server_ip)
        c.connect()
        c.acquire(ports = [0])
        # prepare our ports (my machine has 0 <--> 1 with static route)
        c.reset(ports = [0])

        # clear the stats before injecting
        c.clear_stats()
        c.set_port_attr(ports = [0], promiscuous = True)
        # build packet
        base_pkt = Ether(dst=pkt_dst_mac,src=pkt_src_mac)/Dot1Q(vlan=1)/IP(src="10.0.100.2",dst="10.0.100.1")/UDP(dport=1024,sport=1025)
        #base_pkt = Ether(dst=pkt_dst_mac,src=pkt_src_mac)/IP(src="10.0.100.2",dst="10.0.100.1")/UDP(dport=1024,sport=1025)
        #pad = max(0, 64 - len(base_pkt)) * 'x'
        #pad = 18 * '0'
        pad = max(0, size - len(base_pkt)) * '\x00'
        base_pkt = STLPktBuilder(pkt = base_pkt/pad)

        #stream = STLStream( packet = base_pkt, mode = STLTXCont(),)
        stream = STLStream(isg = 10.0, packet =base_pkt,mode = STLTXMultiBurst( pps = speed, pkts_per_burst = 100000,count=100000000, ibg=1))
        c.add_streams(stream, ports = [0])
        c.start(ports = [0], duration = 30)
        #c.start(ports = [0], mult = "1mpps", duration = 30)
        c.wait_on_traffic(ports = [0])
        c.set_service_mode(ports=[0], enabled=False)
        #print json.dumps(c.get_stats(sync_now = True),indent=4)
	status = c.get_stats(sync_now = True)
        print json.dumps(status, indent=4)
        json.dump(status, open("/home/trex.json", "w"))
        print ("The rx_pps result is %d" %(c.get_stats(sync_now = True))['global']['rx_pps'])
    finally:
        c.disconnect()


import argparse
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Test ovs dpdk bonding trex')

    parser.add_argument('-c','--connect',  type=str,help='trex server ip ',required=True)
    parser.add_argument('-m','--maxcycle', type=int,help='get no loss packets cycle times',required=False)
    parser.add_argument('-t','--time', type=int,help='one time test duration',required=False)
    parser.add_argument('-d','--dst_mac',type=str,help='make packet dst mac address',required=False)
    parser.add_argument('-s','--src_mac',type=str,help='make packet src mac address',required=False)
    parser.add_argument('--pkt_size',type=int,help='init packet size',required=False)
    parser.add_argument('--speed',type=int,help='init speed',required=False)

    args = parser.parse_args()
    print(args)

    server_ip="10.73.130.211"
    size=64
    pkt_dst_mac="52:54:00:11:8F:E8"
    pkt_src_mac="52:54:00:11:8F:E8"

    if args.connect:
        server_ip=args.connect
    if args.dst_mac:
        pkt_dst_mac=args.dst_mac
    if args.src_mac:
        pkt_src_mac=args.src_mac
    if args.pkt_size:
        size=args.pkt_size
    if args.speed:
        speed=args.speed
    stateless()

