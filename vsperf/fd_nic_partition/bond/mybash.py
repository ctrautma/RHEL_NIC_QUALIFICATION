# Copyright (C) 2014  Red Hat
# see file 'COPYING' for use and warranty information
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

"""bash with BeakerLib"""

import io
import os
import sys
import traceback
import subprocess
import select
from threading import Timer
from envbash import load_envbash
import fcntl
import asyncio
import io
import shlex

class bash(object):
    """Manager of a Bash process that is being fed beakerlib commands
    """
    def __init__(self):
        self.beakerlib_file = "/usr/share/beakerlib/beakerlib.sh"
        self.sync_file = "/mnt/tests/kernel/networking/common/lib/lib_nc_sync.sh"
        if os.path.exists(self.beakerlib_file):
            load_envbash(self.beakerlib_file)
        if os.path.exists(self.sync_file):
            load_envbash(self.sync_file)
        else:
            print("Sync File for beaker not find ")

        if 'BEAKERLIB' not in os.environ:
            raise RuntimeError('$BEAKERLIB not set, cannot use BeakerLib')

        self.endof = "echo $?'[---EOF---]'"
        self.env = os.environ
        self.bash = None
        self.loop = asyncio.get_event_loop()
        self.loop.run_until_complete(self.init_process())
        print("init Finish")

    @asyncio.coroutine
    def init_process(self):
        if self.bash == None:
            self.bash = asyncio.create_subprocess_shell("/bin/bash",
            stdin  = asyncio.subprocess.PIPE,
            stdout = asyncio.subprocess.PIPE,
            stderr = asyncio.subprocess.STDOUT,
            env=self.env)
            self.bash = yield from self.bash
        else:
            return
    
    def __call__(self,cmd): 
        return self.run(cmd)
    

    @asyncio.coroutine
    def send_command(self,cmd):
        cmd = bytes(cmd + os.linesep,"utf-8")
        if not self.bash:
            return
        self.bash.stdin.write(cmd)
        self.bash.stdin.write(bytes(self.endof + os.linesep,"utf-8"))
        yield from self.bash.stdin.drain()
    
    @asyncio.coroutine
    def get_out(self):
        all_out = b""
        while True:
            out = yield from self.bash.stdout.readline()
            #print(out)
            if "---EOF---" in out.decode("utf-8"):
                self.code = out.decode("utf-8").split('[')[0]
                break
            else:
                all_out = all_out + out
        #print(all_out)
        return all_out.decode("utf-8")

    #each time can only run one command 
    def run(self, cmd):
        """Given a command as a Popen-style list, run it in the Bash process"""
        if not self.bash:
            return
        self.loop.run_until_complete(self.send_command(cmd))
        self.out = None
        self.err = None
        self.out = self.loop.run_until_complete(self.get_out())
        return self

    def __repr__(self):
        return self.value()

    def __unicode__(self):
        return self.value()

    def __str__(self):
        return self.value()

    def __nonzero__(self):
        return self.__bool__()

    def __bool__(self):
        return bool(self.value())

    def value(self):
        if self.out:
            return self.out.strip()
        return ''

# if __name__ == "__main__":
#     o = bash()
#     o("lssadfdsafds")
#     print(o.code)
#     print(o)
#     o("export abc=1")
#     print(o)
#     print(o.code)
#     o("echo $abc")
#     print(o)
#     print(o.code)
