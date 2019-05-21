#!/usr/bin/env python

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   console.py of /kernel/networking/fd_nic_partition/common/
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

import sys
import os
import logging
import libvirt
from libvirt import VIR_STREAM_EVENT_ERROR, VIR_STREAM_EVENT_HANGUP, VIR_STREAM_EVENT_READABLE, VIR_STREAM_EVENT_WRITABLE
import argparse
import threading


class Console(object):
    def __init__(self):
        pass
    def init(self, name,uri="qemu:///system", user="root", password="redhat"):
        print("Escape character is ^]")
        libvirt.virEventRegisterDefaultImpl()
        self.uri = uri
        self.name = name
        self.connection = libvirt.open(uri)
        self.domain = self.connection.lookupByName(name)
        self.state = self.domain.state(0)
        self.connection.domainEventRegister(lifecycle_callback, self)
        self.user = user
        self.password = password
        self.stream = None
        self.run_console = True
        self.buf = ""
        self.send_init_flag = True
        self.login_flag = False
        self.fin_flag = 0

    def update_cmd_list(self, cmd):
        # import pdb
        # pdb.set_trace()
        self.cmd_list = []
        self.cmd_list.append(cmd)
        #print(self.cmd_list)
        return 

    import threading
    def runconsole(self):
        def test_start():
            if self and self.stream:
                if self.fin_flag >= 3:
                    self.run_console = False
                    return
                stream_callback(self.stream, VIR_STREAM_EVENT_READABLE, self)
            threading.Timer(1, test_start).start()
        timer = threading.Timer(1, test_start)
        timer.start()
        while check_console(self):
            libvirt.virEventRunDefaultImpl()
        return 


def lifecycle_callback(connection, domain, event, detail, console):
    console.state = console.domain.state(0)
    return


def check_console(console):
    if (console.state[0] == libvirt.VIR_DOMAIN_RUNNING or console.state[0] == libvirt.VIR_DOMAIN_PAUSED):
        if console.stream is None:
            console.stream = console.connection.newStream(
                libvirt.VIR_STREAM_NONBLOCK)
            console.domain.openConsole(None, console.stream, 0)
            events = VIR_STREAM_EVENT_READABLE | VIR_STREAM_EVENT_WRITABLE | VIR_STREAM_EVENT_ERROR | VIR_STREAM_EVENT_HANGUP
            console.stream.eventAddCallback(events, stream_callback, console)
    else:
        if console.stream:
            console.stream.eventRemoveCallback()
            console.stream = None
    return console.run_console


def stream_callback(stream, events, console):
    if events & VIR_STREAM_EVENT_READABLE:
        try:
            received_data = console.stream.recv(1)
        except:
            return
        if received_data:
            if console.login_flag == False:
                parse_data_from_guest(console, received_data)
            if not isinstance(received_data, int):
                console.fin_flag = 0
                os.write(0, received_data)
            else:
                console.fin_flag += 1
    elif events & VIR_STREAM_EVENT_WRITABLE:
        if console.send_init_flag:
            console.stream.send('\r\n')
            console.send_init_flag = False
        else:
            if console.login_flag:
                if len(console.cmd_list):
                    temp_cmd = str(console.cmd_list.pop(0)) + "\r\n"
                    stream.send(temp_cmd)
    elif events & VIR_STREAM_EVENT_ERROR or events & VIR_STREAM_EVENT_HANGUP:
        console.run_console = False
        return


def parse_data_from_guest(console, data):
    console.buf += str(data)
    if "Last login:" in str(console.buf):
        console.stream.send('\r\n')
        console.buf = ""
    elif "login:" in str(console.buf):
        console.stream.send(console.user + "\r\n")
        console.buf = ""
    elif "Password:" in str(console.buf):
        console.stream.send(console.password + "\r\n")
        console.buf = ""
    elif "Login incorrect" in str(console.buf):
        console.stream.send('\r\n')
        console.run_console = False
    else:
        if "[root@" in console.buf and str(console.buf).strip()[-1] == "#":
            console.login_flag = True
            console.buf = ""
    return

import threading
def main():
    parser = argparse.ArgumentParser(description='virsh automate console ')
    parser.add_argument('--dom', type=str,
                        help='dom name that you want to login')
    parser.add_argument('--uri', default="qemu:///system",
                        type=str, help='kvm qemu location')
    parser.add_argument('--user', default="root",
                        type=str, help='guest user name')
    parser.add_argument('--password', default="redhat",
                        type=str, help='password with this user name')
    parser.add_argument('--cmd', type=str, nargs="+",help='command list with this guest')
    args = parser.parse_args()
    print(args)
    if args.dom:
        print("Escape character is ^]")
        libvirt.virEventRegisterDefaultImpl()
        console = Console(args.uri, args.dom, args.user, args.password)
        console.update_cmd_list(args.cmd)

        def test_start():
            if console and console.stream:
                if console.fin_flag >= 3:
                    console.run_console = False
                    return
                stream_callback(
                    console.stream, VIR_STREAM_EVENT_READABLE, console)
            threading.Timer(1, test_start).start()

        
        timer = threading.Timer(1, test_start)
        timer.start()

        while check_console(console):
            libvirt.virEventRunDefaultImpl()
    else:
        parser.print_help()
        exit(0)

if __name__ == "__main__":
    import fire
    fire.Fire(Console)
