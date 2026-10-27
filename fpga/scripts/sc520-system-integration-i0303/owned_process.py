"""Draft Windows process ownership for the separately permitted I0303 miter."""

import os
import math
import subprocess
import sys
import time
import traceback


def run_owned_process(command, cwd, stdout, stderr, timeout_seconds, environment, on_started,
                      on_created=None, wall_deadline=None):
    """Create suspended, assign a non-breakaway job, and only then resume."""
    result = {
        "RootCreated": False,
        "RootResumed": False,
        "JobAssignedBeforeResume": False,
        "JobMembershipVerified": False,
        "ResumeRequested": False,
        "ResumeReturnValue": None,
        "ResumeLastError": None,
        "ExpectedResumeVerified": False,
        "NativeExit": None,
        "NaturalNativeExit": False,
        "ExitObservationMeaning": "Root wait signaled before the owner requested termination; external termination is not disproved",
        "HardStopLimitation": "A caller hard-kill between CreateProcess and Assign can leave a suspended root; ordinary finally cleanup is a different scope",
        "TimedOut": False,
        "TerminationRequested": False,
        "TreeCleanVerified": False,
        "Error": None,
        "CleanupErrors": [],
        "StdioDuplicates": [],
        "HandleCleanup": [],
    }
    process = thread = job = None
    kernel = winapi = None
    duplicates = []
    started = time.monotonic()
    try:
        if (
            type(timeout_seconds) not in (int, float) or not math.isfinite(timeout_seconds)
            or timeout_seconds < 0.001
            or (wall_deadline is not None and (
                type(wall_deadline) not in (int, float) or not math.isfinite(wall_deadline)
            ))
        ):
            raise RuntimeError("A finite positive native wait budget is required")
        deadline = min(started + timeout_seconds, wall_deadline) if wall_deadline is not None else started + timeout_seconds

        def remaining_seconds():
            remaining = deadline - time.monotonic()
            if remaining < 0.001:
                result["TimedOut"] = True
                raise RuntimeError("Owned native wall budget expired before the next lifecycle action")
            return remaining

        remaining_seconds()
        if sys.platform != "win32" or sys.version_info[:2] != (3, 12):
            raise RuntimeError("This draft requires the bound Windows CPython 3.12")
        import _winapi
        import ctypes
        import msvcrt
        from ctypes import wintypes

        winapi = _winapi
        if ctypes.sizeof(ctypes.c_void_p) != 8:
            raise RuntimeError("This draft requires the bound 64-bit runtime")

        class BasicLimits(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", ctypes.c_longlong),
                ("PerJobUserTimeLimit", ctypes.c_longlong),
                ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t),
                ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t),
                ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD),
            ]

        class IOCounters(ctypes.Structure):
            _fields_ = [
                (name, ctypes.c_ulonglong)
                for name in (
                    "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
                    "ReadTransferCount", "WriteTransferCount", "OtherTransferCount",
                )
            ]

        class ExtendedLimits(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", BasicLimits),
                ("IoInfo", IOCounters),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        class Accounting(ctypes.Structure):
            _fields_ = [
                ("TotalUserTime", ctypes.c_longlong),
                ("TotalKernelTime", ctypes.c_longlong),
                ("ThisPeriodTotalUserTime", ctypes.c_longlong),
                ("ThisPeriodTotalKernelTime", ctypes.c_longlong),
                ("TotalPageFaultCount", wintypes.DWORD),
                ("TotalProcesses", wintypes.DWORD),
                ("ActiveProcesses", wintypes.DWORD),
                ("TotalTerminatedProcesses", wintypes.DWORD),
            ]

        kernel = ctypes.WinDLL("kernel32.dll", use_last_error=True)
        signatures = {
            "CreateJobObjectW": ([ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
            "SetInformationJobObject": (
                [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], wintypes.BOOL,
            ),
            "AssignProcessToJobObject": ([wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            "IsProcessInJob": (
                [wintypes.HANDLE, wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)], wintypes.BOOL,
            ),
            "ResumeThread": ([wintypes.HANDLE], wintypes.DWORD),
            "TerminateJobObject": ([wintypes.HANDLE, wintypes.UINT], wintypes.BOOL),
            "QueryInformationJobObject": (
                [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD,
                 ctypes.POINTER(wintypes.DWORD)], wintypes.BOOL,
            ),
            "GetProcessTimes": (
                [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4, wintypes.BOOL,
            ),
        }
        for name, (arguments, returns) in signatures.items():
            function = getattr(kernel, name)
            function.argtypes = arguments
            function.restype = returns

        def checked(value, operation):
            if not value:
                raise ctypes.WinError(ctypes.get_last_error(), operation)
            return value

        def accounting():
            value = Accounting()
            checked(kernel.QueryInformationJobObject(
                job, 1, ctypes.byref(value), ctypes.sizeof(value), None,
            ), "QueryInformationJobObject")
            return {
                "TotalProcesses": int(value.TotalProcesses),
                "ActiveProcesses": int(value.ActiveProcesses),
                "TotalTerminatedProcesses": int(value.TotalTerminatedProcesses),
            }

        def wait_empty(seconds):
            deadline = time.monotonic() + seconds
            value = accounting()
            while value["ActiveProcesses"] and time.monotonic() < deadline:
                time.sleep(0.05)
                value = accounting()
            return value

        def close_duplicate(state, phase):
            if state["Closed"]:
                return
            try:
                winapi.CloseHandle(state["Handle"])
                state["Closed"] = True
                result["HandleCleanup"].append({
                    "Kind": "stdio-duplicate", "Handle": state["Handle"], "Phase": phase, "Closed": True,
                })
            except BaseException as error:
                message = f"{type(error).__name__}: {error}"
                state["CloseErrors"].append({"Phase": phase, "Error": message})
                result["CleanupErrors"].append(f"{phase} stdio handle {state['Handle']}: {message}")
                result["HandleCleanup"].append({
                    "Kind": "stdio-duplicate", "Handle": state["Handle"], "Phase": phase,
                    "Closed": False, "Error": message,
                })

        job = checked(kernel.CreateJobObjectW(None, None), "CreateJobObjectW")
        limits = ExtendedLimits()
        limits.BasicLimitInformation.LimitFlags = 0x00002000  # KILL_ON_JOB_CLOSE only.
        checked(kernel.SetInformationJobObject(
            job, 9, ctypes.byref(limits), ctypes.sizeof(limits),
        ), "SetInformationJobObject")

        # Match the bound CPython subprocess implementation's explicit handle list.
        with open(os.devnull, "rb") as stdin:
            handles = [msvcrt.get_osfhandle(stream.fileno()) for stream in (stdin, stdout, stderr)]
            try:
                for handle in handles:
                    duplicate = winapi.DuplicateHandle(
                        winapi.GetCurrentProcess(), handle, winapi.GetCurrentProcess(),
                        0, True, winapi.DUPLICATE_SAME_ACCESS,
                    )
                    duplicates.append({"Handle": int(duplicate), "Closed": False, "CloseErrors": []})
                result["StdioDuplicates"] = duplicates
                startup = subprocess.STARTUPINFO()
                startup.dwFlags = winapi.STARTF_USESTDHANDLES
                stdio = [state["Handle"] for state in duplicates]
                startup.hStdInput, startup.hStdOutput, startup.hStdError = stdio
                startup.lpAttributeList = {"handle_list": stdio}
                flags = subprocess.CREATE_NO_WINDOW | 0x00000004  # CREATE_SUSPENDED.
                remaining_seconds()
                process, thread, pid, tid = winapi.CreateProcess(
                    command[0], subprocess.list2cmdline(command), None, None, True,
                    flags, environment, str(cwd), startup,
                )
                result.update(
                    RootCreated=True, PID=pid, ThreadID=tid, Command=command, Cwd=str(cwd),
                    CreatedProcessHandle=int(process), CreatedThreadHandle=int(thread),
                )
                if on_created is not None:
                    on_created(dict(result))
            finally:
                result["StdioDuplicates"] = duplicates
                for state in duplicates:
                    close_duplicate(state, "post-create")

        if result["CleanupErrors"] or any(not state["Closed"] for state in duplicates):
            raise RuntimeError("Stdio duplicate cleanup failed; root must not resume")
        times = [wintypes.FILETIME() for _ in range(4)]
        checked(kernel.GetProcessTimes(
            process, *(ctypes.byref(value) for value in times),
        ), "GetProcessTimes")
        result["CreationFileTime100ns"] = (
            int(times[0].dwHighDateTime) << 32
        ) | int(times[0].dwLowDateTime)

        checked(kernel.AssignProcessToJobObject(job, process), "AssignProcessToJobObject")
        result["JobAssignedBeforeResume"] = True
        member = wintypes.BOOL()
        checked(kernel.IsProcessInJob(process, job, ctypes.byref(member)), "IsProcessInJob")
        if not member.value:
            raise RuntimeError("Suspended root is not in this job")
        result["JobMembershipVerified"] = True
        result["AssignedAccounting"] = accounting()
        if result["AssignedAccounting"]["ActiveProcesses"] != 1:
            raise RuntimeError("Unexpected process count before root resume")
        remaining_seconds()
        result["ResumeRequested"] = True
        suspension_count = int(kernel.ResumeThread(thread))
        result["ResumeReturnValue"] = suspension_count
        result["ResumeLastError"] = int(ctypes.get_last_error()) if suspension_count == 0xFFFFFFFF else None
        if suspension_count != 1:
            raise RuntimeError(f"Unexpected primary-thread suspension count: {suspension_count}")
        result["ExpectedResumeVerified"] = True
        result["RootResumed"] = True
        on_started(dict(result))
        winapi.CloseHandle(thread)
        result["HandleCleanup"].append({
            "Kind": "thread", "Handle": int(thread), "Phase": "post-resume", "Closed": True,
        })
        thread = None

        remaining = remaining_seconds()
        status = winapi.WaitForSingleObject(process, int(remaining * 1000))
        if status == winapi.WAIT_TIMEOUT:
            result["TimedOut"] = True
            result["TerminationRequested"] = True
            result["PreTerminationAccounting"] = accounting()
            checked(kernel.TerminateJobObject(job, 124), "TerminateJobObject timeout")
            status = winapi.WaitForSingleObject(process, 30000)
        elif status == winapi.WAIT_OBJECT_0:
            result["NaturalNativeExit"] = True
        if status != winapi.WAIT_OBJECT_0:
            raise RuntimeError(f"Owned native process did not terminate: wait={status}")
        result["NativeExit"] = int(winapi.GetExitCodeProcess(process))
        result["FinalAccounting"] = wait_empty(30)
        result["TreeCleanVerified"] = result["FinalAccounting"]["ActiveProcesses"] == 0
        if not result["TreeCleanVerified"]:
            raise RuntimeError("Descendants remained after the native root terminated")
    except BaseException as error:
        result["Error"] = f"{type(error).__name__}: {error}"
        result["Traceback"] = traceback.format_exc()
    finally:
        # Never identify or terminate a process by a reusable PID or a name pattern.
        if process is not None and winapi is not None:
            try:
                running = winapi.WaitForSingleObject(process, 0) != winapi.WAIT_OBJECT_0
                if result["Error"] or running or not result["TreeCleanVerified"]:
                    result["TerminationRequested"] = True
                    if result["JobAssignedBeforeResume"]:
                        checked(kernel.TerminateJobObject(job, 125), "TerminateJobObject cleanup")
                    elif running:
                        winapi.TerminateProcess(process, 125)
                    status = winapi.WaitForSingleObject(process, 30000)
                    if status != winapi.WAIT_OBJECT_0:
                        raise RuntimeError("Cleanup could not reap the suspended or owned root")
                    result["NativeExit"] = int(winapi.GetExitCodeProcess(process))
                    if result["JobAssignedBeforeResume"]:
                        result["CleanupAccounting"] = wait_empty(30)
                        result["TreeCleanVerified"] = (
                            result["CleanupAccounting"]["ActiveProcesses"] == 0
                        )
                    else:
                        result["TreeCleanVerified"] = not result["RootResumed"]
            except BaseException as error:
                result["CleanupErrors"].append(f"{type(error).__name__}: {error}")
        for state in duplicates:
            if not state["Closed"] and winapi is not None:
                close_duplicate(state, "finally")
        for kind, handle in (("thread", thread), ("process", process), ("job", job)):
            if handle is not None and winapi is not None:
                try:
                    winapi.CloseHandle(handle)
                    result["HandleCleanup"].append({"Kind": kind, "Handle": int(handle), "Closed": True})
                except BaseException as error:
                    result["CleanupErrors"].append(f"{type(error).__name__}: {error}")
                    result["HandleCleanup"].append({
                        "Kind": kind, "Handle": int(handle), "Closed": False,
                        "Error": f"{type(error).__name__}: {error}",
                    })
        result["StdioUnclosedHandles"] = [state["Handle"] for state in duplicates if not state["Closed"]]
        if result["CleanupErrors"] or result["StdioUnclosedHandles"]:
            result["TreeCleanVerified"] = False
        result["ElapsedSeconds"] = time.monotonic() - started
    return result
