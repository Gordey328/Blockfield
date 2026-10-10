"""Loopback-only raw TCP delay harness; no third-party dependencies or TLS service."""
from __future__ import annotations

import argparse
from collections import deque
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import time


class Relay:
    MAX_READ = 16384

    def __init__(self, upstream: int, delay_ms: int = 40, max_connections: int = 8,
                 max_buffer: int = 262144):
        if not 1 <= upstream <= 65535 or not 0 <= delay_ms <= 500 or not 1 <= max_connections <= 32 or not 16384 <= max_buffer <= 1048576:
            raise ValueError("invalid bounded relay configuration")
        self.delay = delay_ms / 1000
        self.max_connections = max_connections
        self.max_buffer = max_buffer
        self.selector = selectors.DefaultSelector()
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(max_connections)
        self.listener.setblocking(False)
        self.selector.register(self.listener, selectors.EVENT_READ, None)
        self.port = self.listener.getsockname()[1]
        self.upstream = upstream
        self.pairs = {}
        self.next_id = 1
        self.stats = {"accepted": 0, "closed": 0, "rejected": 0,
                      "errors": 0, "peak_connections": 0, "peak_buffer_bytes": 0,
                      "peak_segments": 0, "received_bytes": 0, "sent_bytes": 0}
        self.directions = {name: {"count": 0, "sum_ms": 0., "min_ms": None,
                                  "max_ms": 0., "samples": deque(maxlen=4096)}
                           for name in ("client_to_server", "server_to_client")}
        self.stalls = []

    def stall(self, connection: int, duration_ms: int) -> dict:
        if connection not in self.pairs or not 1 <= duration_ms <= 3000 or len(self.stalls) >= 16:
            raise ValueError("unknown relay connection or invalid bounded stall")
        now = time.monotonic()
        self.pairs[connection]["blocked_until"] = now + duration_ms / 1000
        record = {"connection": connection, "requested_ms": duration_ms,
                  "started": now, "released": None}
        self.stalls.append(record)
        return {"connection": connection, "duration_ms": duration_ms}

    def _accept(self):
        for _ in range(8):
            try:
                client, _address = self.listener.accept()
            except BlockingIOError:
                break
            if len(self.pairs) >= self.max_connections:
                self.stats["rejected"] += 1
                client.close()
                continue
            client.setblocking(False)
            upstream = socket.socket()
            upstream.setblocking(False)
            upstream.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            for stream in (client, upstream):
                stream.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16384)
                stream.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16384)
            upstream.connect_ex(("127.0.0.1", self.upstream))
            identity = self.next_id
            self.next_id += 1
            pair = {"id": identity, "sockets": [client, upstream],
                    "connecting": True, "queues": [deque(), deque()],
                    "bytes": [0, 0], "eof": [False, False],
                    "shutdown": [False, False], "blocked_until": 0.,
                    "created": time.monotonic(), "last_io": time.monotonic()}
            self.pairs[identity] = pair
            self.stats["accepted"] += 1
            self.stats["peak_connections"] = max(self.stats["peak_connections"], len(self.pairs))
            self._interest(pair, time.monotonic())

    def _interest(self, pair, now):
        for side, stream in enumerate(pair["sockets"]):
            mask = 0
            if side == 1 and pair["connecting"]:
                mask = selectors.EVENT_WRITE
            elif not pair["connecting"]:
                if not pair["eof"][side] and pair["bytes"][side] < self.max_buffer and len(pair["queues"][side]) < 4096:
                    mask |= selectors.EVENT_READ
                pending = pair["queues"][1 - side]
                if pending and now >= max(pair["blocked_until"], pending[0][0]):
                    mask |= selectors.EVENT_WRITE
            try:
                existing = self.selector.get_key(stream)
            except KeyError:
                existing = None
            if not mask:
                if existing is not None:
                    self.selector.unregister(stream)
            elif existing is None:
                self.selector.register(stream, mask, (pair["id"], side))
            elif existing.events != mask:
                self.selector.modify(stream, mask, (pair["id"], side))

    def _close(self, pair, error=False):
        if pair["id"] not in self.pairs:
            return
        for stream in pair["sockets"]:
            try:
                self.selector.unregister(stream)
            except KeyError:
                pass
            stream.close()
        self.pairs.pop(pair["id"])
        self.stats["closed"] += 1
        if error:
            self.stats["errors"] += 1

    def poll(self):
        now = time.monotonic()
        for pair in list(self.pairs.values()):
            if now - pair["last_io"] >= 15:
                self._close(pair, True)
                continue
            self._interest(pair, now)
        for key, mask in self.selector.select(0):
            if key.data is None:
                self._accept()
                continue
            identity, side = key.data
            pair = self.pairs.get(identity)
            if pair is None:
                continue
            stream = pair["sockets"][side]
            try:
                if side == 1 and pair["connecting"]:
                    if stream.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR):
                        raise OSError("upstream connect failed")
                    pair["connecting"] = False
                elif mask & selectors.EVENT_READ:
                    data = stream.recv(min(self.MAX_READ, self.max_buffer - pair["bytes"][side]))
                    if not data:
                        pair["eof"][side] = True
                    else:
                        pair["queues"][side].append([now + self.delay, data, 0, now])
                        pair["bytes"][side] += len(data)
                        pair["last_io"] = now
                        self.stats["received_bytes"] += len(data)
                        self.stats["peak_buffer_bytes"] = max(self.stats["peak_buffer_bytes"], max(pair["bytes"]))
                        self.stats["peak_segments"] = max(self.stats["peak_segments"], max(map(len, pair["queues"])))
                if not pair["connecting"] and mask & selectors.EVENT_WRITE:
                    direction = 1 - side
                    pending = pair["queues"][direction]
                    if pending and now >= max(pair["blocked_until"], pending[0][0]):
                        segment = pending[0]
                        sent = stream.send(memoryview(segment[1])[segment[2]:])
                        segment[2] += sent
                        pair["bytes"][direction] -= sent
                        pair["last_io"] = now
                        self.stats["sent_bytes"] += sent
                        if segment[2] == len(segment[1]):
                            pending.popleft()
                            metrics = self.directions["client_to_server" if direction == 0 else "server_to_client"]
                            elapsed = (now - segment[3]) * 1000
                            metrics["count"] += 1; metrics["sum_ms"] += elapsed
                            metrics["min_ms"] = elapsed if metrics["min_ms"] is None else min(metrics["min_ms"], elapsed)
                            metrics["max_ms"] = max(metrics["max_ms"], elapsed)
                            metrics["samples"].append(elapsed)
                for direction in range(2):
                    target = 1 - direction
                    if pair["eof"][direction] and not pair["queues"][direction] and not pair["shutdown"][target]:
                        pair["sockets"][target].shutdown(socket.SHUT_WR)
                        pair["shutdown"][target] = True
                if all(pair["eof"]) and not any(pair["queues"]):
                    self._close(pair)
            except BlockingIOError:
                pass
            except OSError:
                self._close(pair, True)
        for stall in self.stalls:
            if stall["released"] is None and now >= stall["started"] + stall["requested_ms"] / 1000:
                stall["released"] = now

    def report(self):
        result = dict(self.stats)
        result.update({"connections": len(self.pairs), "delay_ms_each_direction": self.delay * 1000,
                       "max_buffer_per_direction": self.max_buffer, "max_connections": self.max_connections,
                       "directions": {}, "stalls": []})
        for name, metrics in self.directions.items():
            ordered = sorted(metrics["samples"])
            result["directions"][name] = {"delivered_chunks": metrics["count"], "mean_ms": metrics["sum_ms"] / metrics["count"] if metrics["count"] else None,
                                         "min_ms": metrics["min_ms"], "max_ms": metrics["max_ms"],
                                         "sampled_p95_ms": ordered[int(.95 * (len(ordered) - 1))] if ordered else None}
        for stall in self.stalls:
            result["stalls"].append({"connection": stall["connection"], "requested_ms": stall["requested_ms"],
                                     "observed_release_ms": (stall["released"] - stall["started"]) * 1000 if stall["released"] else None})
        return result

    def stop(self):
        for pair in list(self.pairs.values()):
            self._close(pair)
        self.selector.unregister(self.listener)
        self.listener.close()
        self.selector.close()


class OwnedWindowsJob:
    """Assign a suspended owned process before it can create child processes."""
    def __init__(self, process):
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        class Basic(ctypes.Structure):
            _fields_ = [("process_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
                        ("flags", wintypes.DWORD), ("min_work", ctypes.c_size_t), ("max_work", ctypes.c_size_t),
                        ("active", wintypes.DWORD), ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD), ("scheduling", wintypes.DWORD)]
        class IO(ctypes.Structure):
            _fields_ = [(name, ctypes.c_ulonglong) for name in ("read", "write", "other", "read_bytes", "write_bytes", "other_bytes")]
        class Limits(ctypes.Structure):
            _fields_ = [("basic", Basic), ("io", IO), ("process_memory", ctypes.c_size_t),
                        ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
        class Thread(ctypes.Structure):
            _fields_ = [("size", wintypes.DWORD), ("usage", wintypes.DWORD), ("id", wintypes.DWORD),
                        ("owner", wintypes.DWORD), ("priority", wintypes.LONG), ("delta", wintypes.LONG), ("flags", wintypes.DWORD)]
        self.kernel.CreateJobObjectW.restype = wintypes.HANDLE
        self.kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self.kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        self.kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.handle = self.kernel.CreateJobObjectW(None, None)
        limits = Limits(); limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.handle or not self.kernel.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)) or not self.kernel.AssignProcessToJobObject(self.handle, wintypes.HANDLE(int(process._handle))):
            self.close(); raise OSError("owned process job assignment failed")
        self.kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        self.kernel.OpenThread.restype = wintypes.HANDLE
        self.kernel.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.Thread32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(Thread)]
        self.kernel.Thread32Next.argtypes = [wintypes.HANDLE, ctypes.POINTER(Thread)]
        self.kernel.ResumeThread.argtypes = [wintypes.HANDLE]
        self.kernel.ResumeThread.restype = wintypes.DWORD
        snapshot = self.kernel.CreateToolhelp32Snapshot(4, 0)
        entry = Thread(); entry.size = ctypes.sizeof(entry)
        resumed = False
        try:
            more = self.kernel.Thread32First(snapshot, ctypes.byref(entry))
            while more:
                if entry.owner == process.pid:
                    thread = self.kernel.OpenThread(2, False, entry.id)
                    if thread:
                        resumed = self.kernel.ResumeThread(thread) != 0xffffffff
                        self.kernel.CloseHandle(thread)
                    break
                more = self.kernel.Thread32Next(snapshot, ctypes.byref(entry))
        finally:
            self.kernel.CloseHandle(snapshot)
        if not resumed:
            self.close(); raise OSError("owned suspended process resume failed")

    def close(self):
        if getattr(self, "handle", None):
            self.kernel.CloseHandle(self.handle); self.handle = None


def write_json(path: Path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    os.replace(temporary, path)


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
    except (OSError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--test", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--deadline", type=float, default=45)
    args = parser.parse_args()
    if not args.godot.is_absolute() or not args.project.is_absolute() or not args.godot.is_file() or not (args.project / "project.godot").is_file() or not 5 <= args.deadline <= 45:
        parser.error("absolute existing --godot/--project paths and deadline5..45 required")
    test = args.test.resolve() if args.test else Path(__file__).resolve().parent.parent / "tests/network/test_network_latency.gd"
    if not test.is_file(): parser.error("test script does not exist")
    cache = args.project.parent / ".cache"; cache.mkdir(exist_ok=True)
    task = Path(tempfile.mkdtemp(prefix="network-latency-", dir=cache))
    report_path = args.report.resolve() if args.report else cache / "benchmarks/network-latency.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    log_path = report_path.with_suffix(".log")
    relays = {}
    process = None; job = None; result = None; error = ""; exit_code = None; requests = 0
    start = time.monotonic()
    # Reserve three seconds of the requested whole deadline for owned-tree
    # termination and socket cleanup; do not add six seconds after it expires.
    drive_deadline = start + args.deadline - 3
    try:
        flags = (0x4 | 0x08000000 | 0x200) if os.name == "nt" else 0
        with log_path.open("wb") as log:
            process = subprocess.Popen([str(args.godot), "--headless", "--path", str(args.project), "--script", str(test), "--", "--latency-dir=" + str(task)],
                                       stdout=log, stderr=subprocess.STDOUT, cwd=args.project.parent, creationflags=flags,
                                       start_new_session=os.name != "nt")
            if os.name == "nt": job = OwnedWindowsJob(process)
            while time.monotonic() < drive_deadline:
                status = read_json(task / "status.json")
                if status and status.get("phase") == "ready" and not relays:
                    relays = {name: Relay(int(status[name + "_port"])) for name in ("game", "map")}
                    write_json(task / "control.json", {"game_port": relays["game"].port, "map_port": relays["map"].port, "ack": 0})
                request = read_json(task / "request.json")
                if request and int(request.get("sequence", 0)) > requests:
                    if requests >= 16 or int(request["sequence"]) != requests + 1 or request.get("action") != "stall" or request.get("channel") not in relays:
                        raise ValueError("invalid trusted control request")
                    applied = relays[request["channel"]].stall(int(request["connection"]), int(request["duration_ms"]))
                    requests += 1
                    write_json(task / "control.json", {"game_port": relays["game"].port, "map_port": relays["map"].port, "ack": requests, "stall": applied})
                for relay in relays.values(): relay.poll()
                if process.poll() is not None:
                    exit_code = process.returncode; result = read_json(task / "result.json"); break
                time.sleep(.001)
            else:
                error = "bounded whole-run deadline exceeded"
    except Exception as exc:
        # Only fixed control/OS error descriptions, never payload/credential bytes.
        error = type(exc).__name__ + ": " + str(exc)
    finally:
        if process is not None and process.poll() is None:
            if job: job.close()
            elif os.name != "nt":
                import signal
                os.killpg(process.pid, signal.SIGTERM)
            else: process.terminate()
            try: process.wait(timeout=1.5)
            except subprocess.TimeoutExpired:
                if os.name != "nt":
                    import signal
                    os.killpg(process.pid, signal.SIGKILL)
                else: process.kill()
                process.wait(timeout=1.5)
            exit_code = process.returncode
        if job: job.close()
        for relay in relays.values(): relay.stop()
    report = {"ok": not error and exit_code == 0 and bool(result) and result.get("failures") == 0,
              "error": error, "godot_exit": exit_code, "wall_seconds": time.monotonic() - start,
              "deadline_seconds": args.deadline, "loopback_only": True, "tcp_shaping_not_wan": True,
              "owned_process_cleanup": "suspended Windows Job Object" if os.name == "nt" else "owned process group",
              "godot": result, "relays": {name: relay.report() for name, relay in relays.items()}}
    write_json(report_path, report)
    print(json.dumps({"ok": report["ok"], "wall_seconds": report["wall_seconds"], "godot_exit": exit_code,
                      "error": error, "assertions": result.get("assertions") if result else None,
                      "failures": result.get("failures") if result else None, "report": str(report_path), "log": str(log_path)}))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
