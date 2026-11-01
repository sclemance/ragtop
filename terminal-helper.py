#!/usr/bin/python3
"""Isolated terminal completion. JSON requests/replies carry an opaque id.

Only command metadata is cached. Requests are not logged or persisted. Slow
PATH/directory access cannot block the separate word/swipe predictor. Manual
notes arrive later, tagged with the same id so the UI can reject stale updates.
"""
import json
import os
import selectors
import signal
import subprocess
import sys
import time

from predictor import Terminal


def reply(request_id, items, update=False):
    print(json.dumps({'id': request_id, 'items': items, 'update': update},
                     ensure_ascii=False), flush=True)


class Worker:
    def __init__(self):
        self.terminal = Terminal(load_notes=False)
        self.selector = selectors.DefaultSelector()
        self.notes_proc = None
        self.notes_attempted = False
        self.notes_output = bytearray()
        self.notes_deadline = 0
        self.latest = None
        self.input = bytearray()

    def stop_notes(self):
        proc = self.notes_proc
        if proc is None:
            return
        # Shutdown can interrupt startup before the pipe was registered.
        try:
            self.selector.unregister(proc.stdout)
        except (KeyError, ValueError):
            pass
        proc.stdout.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                proc.kill()
        proc.wait()
        self.notes_proc = None
        self.notes_output.clear()

    def start_notes(self):
        if self.notes_attempted or self.terminal.commands is None:
            return
        self.notes_attempted = True
        try:
            self.notes_proc = subprocess.Popen(['apropos', '-l', '-s', '1,8', '.'],
                                               stdin=subprocess.DEVNULL,
                                               stdout=subprocess.PIPE,
                                               stderr=subprocess.DEVNULL)
        except OSError:
            return
        os.set_blocking(self.notes_proc.stdout.fileno(), False)
        self.selector.register(self.notes_proc.stdout, selectors.EVENT_READ, 'notes')
        self.notes_deadline = time.monotonic() + 5

    def request(self, raw):
        self.latest = None
        request_id = None
        items = []
        try:
            req = json.loads(raw)
            if not isinstance(req, dict):
                raise ValueError()
            if req.get('reset') is True:
                return  # Drop request-specific notes; keep command metadata.
            request_id = req['id']
            if type(request_id) is not int:
                raise ValueError()
            cwd, line = req['cwd'], req['line']
            shell = req.get('shell', 'bash')
            if not isinstance(cwd, str) or not os.path.isabs(cwd) or not isinstance(line, str) or shell == 'nu':
                raise ValueError()
            old_shell = self.terminal.shell
            self.terminal.set_shell(shell)
            if self.terminal.shell != old_shell:
                self.stop_notes()
                self.notes_attempted = False
                self.terminal.notes.clear()
            items = self.terminal.suggest(cwd, line)
        except (ValueError, KeyError, TypeError, OSError):
            pass
        reply(request_id, items)
        # Only command names need a later description; never retain the
        # command line or filesystem suggestions while awaiting metadata.
        if items and all(item['kind'] == 'command' for item in items):
            self.latest = (request_id, items)
            self.start_notes()

    def notes_ready(self):
        data = os.read(self.notes_proc.stdout.fileno(), 65536)
        if data:
            self.notes_output.extend(data)
            if len(self.notes_output) > 8 * 1024 * 1024:
                self.stop_notes()
            return
        self.terminal.read_notes(self.notes_output.decode(errors='replace'))
        self.stop_notes()
        if self.latest:
            request_id, items = self.latest
            for item in items:
                note = self.terminal.notes.get(item['text'], '')
                item['note'] = note if len(note) <= 30 else note[:29].rstrip() + '\u2026'
            reply(request_id, items, update=True)
            self.latest = None

    def run(self):
        self.selector.register(sys.stdin, selectors.EVENT_READ, 'input')
        print('{"ready": true}', flush=True)
        try:
            while True:
                timeout = max(0, self.notes_deadline - time.monotonic()) if self.notes_proc else None
                for key, _ in self.selector.select(timeout):
                    if key.data == 'notes':
                        # An input event may have cancelled/replaced this job.
                        if self.notes_proc and key.fileobj is self.notes_proc.stdout:
                            self.notes_ready()
                        continue
                    data = os.read(sys.stdin.fileno(), 65536)
                    if not data:
                        return
                    self.input.extend(data)
                    del data
                    while b'\n' in self.input:
                        raw, _, rest = self.input.partition(b'\n')
                        self.input = bytearray(rest)
                        if raw == b'quit':
                            return
                        self.request(raw)
                        del raw, rest
                    if len(self.input) > 1024 * 1024:
                        return
                if self.notes_proc and time.monotonic() >= self.notes_deadline:
                    self.stop_notes()
        finally:
            self.latest = None
            self.input.clear()
            self.stop_notes()
            self.selector.close()


if __name__ == '__main__':
    def terminate(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    try:
        Worker().run()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    except Exception:
        # Never include a request, path or exception text in shell logs.
        print('terminal helper failed', file=sys.stderr)
        sys.exit(1)
