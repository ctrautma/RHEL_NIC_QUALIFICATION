import sys, getopt

sys.path.append('./v2.48/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./v2.49/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.49/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./v2.53/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.53/automation/trex_control_plane/stf/trex_stf_lib/')

#sys.path.append('/home/wanghekai/soft/v2.48/automation/trex_control_plane/interactive/trex/examples/stl')
#sys.path.append('/home/wanghekai/soft/v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
import stl_path
from trex_stl_lib.api import *
import json
print(sys.path)


class TrexTest(object):
    def __init__(self,trex_host):
        self.trex_host=trex_host
        pass
    def conn(self):
        self.conn = STLClient(self.trex_host)
        return self.conn
    def test_conn(self):
        pass


def test_conn_ok(c,ports,streams):
    c.reset(ports = ports)
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

    #return json.dumps(c.get_stats(ports = [0], sync_now = True),indent=4, sort_keys=True)
    #return c.get_stats(ports = [0], sync_now = True)
    #print(json.dumps(c.get_stats(ports = [0], sync_now = True),indent=4,sort_keys=True))
    #print(json.dumps(c.get_pgid_stats(),indent=4,sort_keys=True))
    #return c.get_pgid_stats()
    stat = c.get_pgid_stats()
    print("ports %s Test result " % (str(ports)) )
    print(json.dumps(stat,indent=4,sort_keys=False))
    if stat["flow_stats"][1]["tx_pkts"]["total"] > 0 and stat["flow_stats"][1]["rx_pkts"]["total"] > 0 :
        return True
    else:
        return False


def repeat_through_put(c,rate,duration,ports,streams):
    c.reset(ports = ports)
    c.acquire(ports = ports, force = True)

    # add both streams to ports
    c.add_streams(streams, ports = ports)

    # clear the stats before injecting
    c.clear_stats()

    #c.set_port_attr(ports=[0], promiscuous = True) 

    print("start %s mpps throughput begin " % rate)

    #c.start(ports = [0], mult = str(rate) + "kpps", duration = duration)
    c.start(ports = ports, mult = str(rate) + "mpps", duration = duration)

    #print c.get_stats(ports = [0], sync_now = True)

    #c.wait_on_traffic(ports = [0], timeout= 100)
    c.wait_on_traffic(ports = ports)
    if c.get_warnings():
            print("Warning")

    #return json.dumps(c.get_stats(ports = [0], sync_now = True),indent=4, sort_keys=True)
    #return c.get_stats(ports = [0], sync_now = True)
    #print(json.dumps(c.get_stats(ports = [0], sync_now = True),indent=4,sort_keys=True))
    #print(json.dumps(c.get_pgid_stats(),indent=4,sort_keys=True))
    return c.get_pgid_stats()

import argparse
if __name__ == "__main__":
    #sys.path.append('./v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
    import trex_client
    import trex_status

    parser = argparse.ArgumentParser(description='Test ovs dpdk bonding trex')
    parser.add_argument('-c','--connect',  type=str,help='trex server ip ',required=True)
    parser.add_argument('-m','--maxcycle', type=int,help='get no loss packets cycle times',required=False)
    parser.add_argument('-t','--time', type=int,help='one time test duration',required=False)
    parser.add_argument('-d','--dst_mac',type=str,help='make packet dst mac address',required=False)
    parser.add_argument('-s','--src_mac',type=str,help='make packet src mac address',required=False)
    parser.add_argument('--pkt_size',type=int,help='init packet size',required=False)
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
    
    trex = trex_client.CTRexClient(server_ip)
    print("Before Running, TRex status is: {}".format(trex.is_running()))
    print("Before Running, TRex status is: {}".format(trex.get_running_status()))
    while trex.is_running():
        trex.force_kill(confirm=False)
        time.sleep(5)
        pass
    trex.start_stateless()
    time.sleep(5)
    while trex.is_running() == False:
        trex.start_stateless()
        time.sleep(5)
    print("After Starting, TRex status is: {},{}".format(trex.is_running(),trex.get_running_status()))
    time.sleep(10)
    print("Is TRex running? {},{}".format(trex.is_running(), trex.get_running_status()))


    c = STLClient(server=server_ip)
    #base_pkt =  Ether(dst=pkt_dst_mac)
    
    base_pkt = Ether(dst=pkt_dst_mac)/IP(src="192.168.100.10",
                                         dst="192.168.100.20")/UDP(dport=12, sport=1025)
    pad = max(0, size - len(base_pkt)) * 'x'

    base_stream = STLStream( isg = 10.0, # star in delay
               name    ='S1',
               packet = STLPktBuilder(pkt = base_pkt/pad),
               flow_stats = STLFlowStats(pg_id = 1 ),
               #mode = STLTXSingleBurst( pps = 10, total_pkts = 10)
               #mode= STLTXCont(pps = 10000),
               mode = STLTXCont(percentage = 99)
               )


    """
    #print(stream.to_code())
    base_stream = STLStream( isg = 10.0, # star in delay
               name    ='S1',
               packet = STLPktBuilder(pkt = base_pkt/pad),
               flow_stats = STLFlowStats(pg_id = 1 ),
               #mode = STLTXSingleBurst( pps = 10, total_pkts = 10)
               #mode= STLTXCont(pps = 10000),
               mode = STLTXCont(percentage = 99)
               )
    """

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
                  );

    noise_pkt = STLPktBuilder(pkt = noise_base_pkt/pad,vm = vm)

    stream = STLStream( packet = noise_pkt, mode = STLTXSingleBurst( pps = 100, total_pkts = 3000),
        #flow_stats= STLFlowStats(pg_id = 2)
        )
    

    """
    for i in range(1,10):
        src_ip = "192.168.1." + str(i)
        for j in range(1,10):
            dst_ip="172.16.1." + str(j)
            pkt = Ether(dst=pkt_dst_mac)/ARP(psrc=src_ip,pdst=dst_ip)
            stream = STLStream( isg = 10.0, # star in delay
                name    = str(i) + str(j),
                packet = STLPktBuilder(pkt = pkt/pad),
                #flow_stats = STLFlowStats(pg_id = int(str(i) + str(j))),
                #mode = STLTXSingleBurst( pps = 10, total_pkts = 10)
                #mode= STLTXCont(pps = 0.01 ),
                mode = STLTXCont(percentage = 0.01)
                )
            all_stream.append(stream)
    """

    all_stream.append(base_stream)
    all_stream.append(stream)

    s1 =  STLProfile(streams=all_stream).get_streams()
    #print(s1)


    # connect to server
    #print(c)
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
            pass



    #print(c.get_port_attr(0))

    max_retry=1
    duration=10
    if args.maxcycle:
        max_retry=args.maxcycle
    if args.time:
        duration=args.time

    cur_max=12
    cur_min=0
    try_vlaue=cur_max/2

    last_value=0
    last_result=""

    for i in range(max_retry):
        stat = repeat_through_put(c,try_vlaue,duration,real_ports,s1)
        print(json.dumps(stat,indent=4,sort_keys=False))
        """
            "total": {
            "ibytes": 679999456, 
            "ierrors": 0, 
            "ipackets": 9999992, 
            "obytes": 679999456, 
            "oerrors": 0, 
            "opackets": 9999992, 
            "rx_bps": 541843776.0, 
            "rx_bps_L1": 701209584.0, 
            "rx_pps": 996036.3, 
            "rx_util": 7.012095840000001, 
            "tx_bps": 541834432.0, 
            "tx_bps_L1": 701197488.0, 
            "tx_pps": 996019.1, 
            "tx_util": 7.01197488

        """
        print("current %s cycle repeat" % i)
        #print(json.dumps(stat["flow_stats"],indent=4, sort_keys=True))
        #print(stat)
        if stat["flow_stats"][1]["tx_pkts"]["total"] > stat["flow_stats"][1]["rx_pkts"]["total"]:
            cur_max = try_vlaue
            try_vlaue = (cur_min + cur_max)/(2 * 1.0)
        else:
            last_value=try_vlaue
            cur_min = try_vlaue
            try_vlaue = (cur_min + cur_max)/(2 * 1.0)
            last_result=json.dumps(stat["flow_stats"][1],indent=4, sort_keys=False)


    print("******************************************************************************")
    print("begine long time test begin %s mpps" % (last_value))
    stat = repeat_through_put(c,last_value/2,600,real_ports,s1)
    print(json.dumps(stat,indent=4,sort_keys=False))
    if stat["flow_stats"][1]["tx_pkts"]["total"] > stat["flow_stats"][1]["rx_pkts"]["total"]:
        last_value = 0
    else:
        pass
    last_result=json.dumps(stat["flow_stats"][1],indent=4, sort_keys=False)
    print("begine long time test end")

    print("************************************************")
    if(0 == last_value):
        print("long time test find lose packets !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    print("last result is",last_value,"mpps")
    print(last_result)
    print("************************************************")


    c.disconnect()
    import sys
    if 0 == last_value:
        sys.exit(3)
    else:
        sys.exit(0)
