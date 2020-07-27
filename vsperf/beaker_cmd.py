#!/usr/bin/env python3

import os
import sys
import time
from bash import bash
from functools import wraps
import contextlib


cmd_file = os.environ.get("CMD_FILE")
lock_file = os.environ.get("LOCK_FILE")

def set_check(ret):
    def my_wrap(f):
        @wraps(f)
        def log_f_as_called(*args, **kwargs):
            my_command = f'{f.__name__} {args} {kwargs}'

            #begin_time = time.asctime().split()[3]

            #cmd = f""":: [ {begin_time} ] :: [  BEGIN   ] :: Running '{my_command}' """
            cmd = f"""[  BEGIN   ] :: Running '{my_command}' """

            log(cmd)

            value = f(*args, **kwargs)

            #end_time = time.asctime().split()[3]

            #cmd = f""" :: [ {end_time} ] :: [   {value}   ] :: Command '{my_command}' """
            cmd = f"""[ END ] [   {value}   ] :: Running '{my_command}' """

            log(cmd)

            return value
        return log_f_as_called
    return my_wrap

def basic_command_send(cmd):
    my_cmd = cmd + os.linesep
    while True:
        if os.stat(cmd_file).st_size > 0:
            time.sleep(0.1)
            continue
        else:
            bash(f"lockfile {lock_file}")
            with open(cmd_file, 'w') as fd:
                fd.write(my_cmd)
                fd.flush()
            bash(f"rm -f {lock_file}")
            break

def send_command(cmd):
    basic_command_send(cmd)
    basic_command_send(os.linesep)
    pass

def log(str_log):
    #logs = str(str_log) + str(os.linesep)
    cmd = f""" rlLog "{str_log}" """
    send_command(cmd)

def run(cmd, str_ret_val="0"):
    my_cmds = cmd + os.linesep
    my_cmds = [ i.strip() for i in my_cmds.split(os.linesep) ]
    for i in my_cmds:
        if len(i) > 0:
            real_cmd = """ rlRun  "{}" "{}" """.format(i, str_ret_val)
            send_command(real_cmd)
    pass

def log_and_run(cmd, str_ret_val="0"):
    log(cmd)
    run(cmd, str_ret_val)
    pass

def rl_fail(cmd):
    cmd = cmd + os.linesep
    real_cmd = """ rlFail  "{}" """.format(cmd)
    send_command(real_cmd)

def shpushd(path):
    cmd = f"""rlRun "pushd {path}" """
    send_command(cmd)
    pass


def shpopd():
    cmd = "rlRun popd"
    send_command(cmd)
    pass


@contextlib.contextmanager
def pushd(path):
    shpushd(path)
    try:
        yield
    finally:
        shpopd()


@contextlib.contextmanager
def enter_phase(str):
    cmd = f""" rlPhaseStartTest '{str}' """
    send_command(cmd)
    time.sleep(1)
    try:
        yield
    finally:
        send_command("rlPhaseEnd")
        time.sleep(1)


def val_check_equal(a, b, str_comm=""):
    ret = 0 if a == b else 1
    if ret == 1:
        cmd = f""" rlFail  "{str_comm}" """
    else:
        cmd = f""" rlPass  "{str_comm}" """
    send_command(cmd)
    pass


def val_check_not_equal(a, b, str_comm=""):
    ret = 1 if a == b else 0
    if ret == 1:
        cmd = f""" rlFail  "{str_comm}" """
    else:
        cmd = f""" rlPass  "{str_comm}" """
    send_command(cmd)

#Must do not remove log line
def sync_set(target,value,timeout=86400):
    log(f"Start sync_set {value}")
    send_command(f"sync_set {target} {value} {timeout}")
    log(f"End sync_set {value}")

#Must do not remove log line
def sync_wait(target,value,timeout=86400):
    log(f"Start sync_wait {value}")
    send_command(f"sync_wait {target} {value} {timeout}")
    log(f"End sync_wait {value}")

