import argparse
import csv
import glob
import os
import re
import sys
import tarfile
import xlsxwriter


class ResultsSheet(object):
    def __init__(self, args):
        self._args = args
        self._workbook = xlsxwriter.Workbook(self._args.output)
        self.client_file = args.client_tar_file
        self.server_file = args.server_tar_file
        self.pvp_dpdk_ws = self._workbook.add_worksheet('pvp__dpdk_results')
        self.pvp_kernel_ws = self._workbook.add_worksheet('pvp_kernel_results')
        self.vsperf_ws = self._workbook.add_worksheet('throughput results')
        self.functional_ws = self._workbook.add_worksheet('functional results')
        self.row = 0

    def process_functional_results(self):
        tar1 = tarfile.open(self.client_file, "r")
        tar2 = tarfile.open(self.server_file, "r")
        self.functional_ws.set_column(0, 4, 30)

        def process_log(tar, member, column):
            self.row = 1
            column = column
            fh1 = tar.extractfile(member)
            data = fh1.readlines()
            for line in data:
                if "RESULT" in line:
                    findresult = re.search('\[   (PASS|FAIL)   \] :: RESULT: (\S+)', line)
                    if findresult:
                        self.functional_ws.write_string(self.row, column, findresult.group(2))
                        self.functional_ws.write_string(self.row, column + 1, findresult.group(1))
                        self.row += 1
        for member in tar1.getnames():
            if 'client.log' in member:
                self.functional_ws.write_string(0, 0, 'Client results')
                process_log(tar1, member, 0)
        for member in tar2.getnames():
            if 'server.log' in member:
                self.functional_ws.write_string(0, 2, 'Server results')
                process_log(tar2, member, 2)

    def process_pvp_results(self):
        # get the pvp result files
        pvp_files = glob.glob('./pvp*.tgz')
        for result_file in pvp_files:
            tar = tarfile.open(result_file, "r:gz")
            # find the dpdk result file and process it
            if 'dpdk' in result_file:
                fh1 = tar.extractfile('root/pvp_results_1_l2_dpdk/test_results_l2.csv')
                fh2 = tar.extractfile('root/pvp_results_1_l3_dpdk/test_results_l3.csv')
                spamreader1 = csv.reader(fh1, delimiter=',', quotechar='|')
                spamreader2 = csv.reader(fh2, delimiter=',', quotechar='|')
                max_column = 0
                for row in spamreader1:
                    column = 0
                    try:
                        if len(row) > 0 and 'cpu' not in row[0]:
                            for i in range(len(row)):
                                self.pvp_dpdk_ws.write_string(self.row, column, row[i])
                                column += 1
                            self.row += 1
                            max_column = column if column > max_column else max_column
                    except IndexError:
                        continue
                for row in spamreader2:
                    column = 0
                    try:
                        if len(row) > 0 and not 'cpu' in row[0]:
                            for i in range(len(row)):
                                self.pvp_dpdk_ws.write_string(self.row, column, row[i])
                                column += 1
                            self.row += 1
                            max_column = column if column > max_column else max_column
                    except IndexError:
                        continue
                self.pvp_dpdk_ws.set_column(0, max_column, 30)
            self.row = 0

            # find the kernel result file and process it
            if 'kernel' in result_file:
                fh1 = tar.extractfile('root/pvp_results_1_l2_kernel/test_results_l2.csv')
                fh2 = tar.extractfile('root/pvp_results_1_l3_kernel/test_results_l3.csv')
                spamreader1 = csv.reader(fh1, delimiter=',', quotechar='|')
                spamreader2 = csv.reader(fh2, delimiter=',', quotechar='|')
                max_column = 0
                for row in spamreader1:
                    column = 0
                    try:
                        if len(row) > 0 and not 'cpu' in row[0]:
                            for i in range(len(row)):
                                self.pvp_kernel_ws.write_string(self.row, column, row[i])
                                column += 1
                            self.row += 1
                            max_column = column if column > max_column else max_column
                    except IndexError:
                        continue
                for row in spamreader2:
                    column = 0
                    try:
                        if len(row) > 0 and not 'cpu' in row[0]:
                            for i in range(len(row)):
                                self.pvp_kernel_ws.write_string(self.row, column, row[i])
                                column += 1
                            self.row += 1
                            max_column = column if column > max_column else max_column
                    except IndexError:
                        continue
                self.pvp_kernel_ws.set_column(0, max_column, 30)
            self.row=0

    def process_throughput_results(self):
        self.vsperf_ws.set_column(0, 2, 30)
        tar = tarfile.open(self.client_file, "r")
        for member in tar.getnames():
            if 'vsperf_result' in member:
                fh1 = tar.extractfile(member)
                data = fh1.readlines()
                for line in data:
                    if "64   Byte 2PMD OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(0, 0, '64 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(0, 1, line.split()[8])
                    elif "1500 Byte 2PMD OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(1, 0, '1500 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(1, 1, line.split()[8])
                    elif "64   Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(2, 0, '64 Byte 4PMD 2Q DPDK')
                        self.vsperf_ws.write_string(2, 1, line.split()[9])
                    elif "1500 Byte 4PMD 2Q OVS/DPDK PVP test result" in line:
                        self.vsperf_ws.write_string(3, 0, '1500 Byte 4PMD 2Q DPDK')
                        self.vsperf_ws.write_string(3, 1, line.split()[9])
                    elif ("2000 Byte 2PMD OVS/DPDK PVP test result" in line or
                                  "2000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
                        self.vsperf_ws.write_string(4, 0, '2000 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(4, 1, line.split()[8])
                    elif ("9000 Byte 2PMD OVS/DPDK PVP test result" in line or
                                  "9000 Byte 2PMD OVS/DPDK Phy2Phy test result" in line):
                        self.vsperf_ws.write_string(5, 0, '9000 Byte 2PMD 1Q DPDK')
                        self.vsperf_ws.write_string(5, 1, line.split()[8])
                    elif "64   Byte OVS Kernel PVP test result" in line:
                        self.vsperf_ws.write_string(6, 0, '64 Byte Kernel')
                        self.vsperf_ws.write_string(6, 1, line.split()[8])
                    elif "1500 Byte OVS Kernel PVP test result" in line:
                        self.vsperf_ws.write_string(7, 0, '1500 Byte Kernel')
                        self.vsperf_ws.write_string(7, 1, line.split()[8])

    def close_workbook(self):
        self._workbook.close()


def main():
    mysheet = ResultsSheet(args)
    mysheet.process_pvp_results()
    mysheet.process_throughput_results()
    mysheet.process_functional_results()
    mysheet.close_workbook()


def yes_no(answer):
    yes = set(['yes', 'y', 'ye', ''])
    no = set(['no', 'n'])

    while True:
        choice = raw_input(answer).lower()
        if choice in yes:
            return True
        elif choice in no:
            return False
        else:
            print("Please respond with 'yes' or 'no'\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-o', '--output', type=str, required=True,
                        help='Output file name')
    parser.add_argument('-s', '--server_tar_file', type=str, required=True,
                        help='Server tar file name')
    parser.add_argument('-c', '--client_tar_file', type=str, required=True,
                        help='Client tar file name')
    args = parser.parse_args()
    if os.path.isfile(args.output):
        ans = yes_no("Output file {} already exists. Overwrite?".format(args.output))
        if not ans:
            sys.exit()
    if os.path.isfile(args.server_tar_file) == False or os.path.isfile(args.client_tar_file) == False:
        print("Server or client file do not exist. Check your arguments.")
    main()
