"""Real isolated worker protocol, metadata delay, and process cleanup."""
import json
import importlib.util
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(sys.argv.pop())


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ['git', 'grep']:
            p = self.bin / name
            p.write_text('#!/bin/sh\nexit 0\n')
            p.chmod(0o700)
        apropos = self.bin / 'apropos'
        apropos.write_text('#!/bin/sh\necho $$ > "$FIXTURE/notes.pid"\n'
                           'while [ ! -e "$FIXTURE/release" ]; do /bin/sleep 0.02; done\n'
                           'echo "git (1) - version control"\necho "grep (1) - find text"\n')
        apropos.chmod(0o700)
        env = dict(os.environ, PATH=str(self.bin), FIXTURE=str(self.root))
        self.proc = subprocess.Popen(['/usr/bin/python3', str(REPO / 'terminal-helper.py')],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, env=env)
        self.buffer = b''
        self.assertEqual(self.read(), {'ready': True})

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.terminate()
        self.proc.communicate(timeout=3)
        self.temp.cleanup()

    def send(self, id, line, shell='bash'):
        data = {'id': id, 'line': line, 'cwd': str(self.root), 'shell': shell}
        self.proc.stdin.write(json.dumps(data).encode() + b'\n')
        self.proc.stdin.flush()

    def read(self, timeout=3):
        end = time.monotonic() + timeout
        while b'\n' not in self.buffer:
            left = end - time.monotonic()
            self.assertGreater(left, 0, 'worker response timed out')
            self.assertTrue(select.select([self.proc.stdout], [], [], left)[0])
            data = os.read(self.proc.stdout.fileno(), 65536)
            self.assertTrue(data, 'worker closed stdout')
            self.buffer += data
        raw, self.buffer = self.buffer.split(b'\n', 1)
        return json.loads(raw)

    def notes_pid(self):
        p = self.root / 'notes.pid'
        end = time.monotonic() + 3
        while not p.exists() and time.monotonic() < end:
            time.sleep(.02)
        return int(p.read_text())

    def test_names_arrive_before_notes_and_predictor_stays_available(self):
        self.send(1, 'gi')
        first = self.read()
        self.assertEqual(first['items'][0]['text'], 'git')
        self.assertEqual(first['items'][0]['note'], '')
        self.notes_pid()  # metadata is held at a barrier
        self.send(2, 'gre')
        self.assertEqual(self.read()['items'][0]['text'], 'grep')
        other = subprocess.run(['/usr/bin/python3', str(REPO / 'predictor.py'), str(self.root / 'words')],
                               input='complete hello\n', text=True, capture_output=True, timeout=3)
        self.assertEqual(other.returncode, 0)
        self.assertIn('suggest []', other.stdout)
        (self.root / 'release').touch()
        update = self.read()
        self.assertTrue(update['update'])
        self.assertEqual(update['id'], 2)
        self.assertEqual(update['items'][0]['note'], 'find text')
        self.send(3, 'gi')
        self.assertEqual(self.read()['items'][0]['note'], 'version control')

    def test_file_escaping_and_no_command_line_in_stderr(self):
        (self.root / 'my docs').mkdir()
        self.send(1, 'cd my')
        self.assertEqual(self.read()['items'][0]['text'], 'my\\ docs/')
        self.send(2, 'private-password', shell='nu')
        self.assertEqual(self.read()['items'], [])
        self.proc.stdin.close(); self.proc.stdin = None
        self.assertEqual(self.proc.wait(timeout=3), 0)
        self.assertEqual(self.proc.stderr.read(), b'')

    def test_eof_and_termination_reap_metadata_child(self):
        self.send(1, 'gi'); self.read()
        pid = self.notes_pid()
        self.proc.send_signal(signal.SIGTERM)
        self.assertEqual(self.proc.wait(timeout=3), 0)
        with self.assertRaises(ProcessLookupError): os.kill(pid, 0)

    def test_missing_metadata_keeps_completion(self):
        (self.bin / 'apropos').unlink()
        self.send(1, 'gi')
        self.assertEqual(self.read()['items'][0]['text'], 'git')
        self.send(2, 'gre')
        self.assertEqual(self.read()['items'][0]['text'], 'grep')

    def test_metadata_timeout_does_not_stop_completion(self):
        self.send(1, 'gi'); self.read()
        pid = self.notes_pid()
        end = time.monotonic() + 7
        while time.monotonic() < end:
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(.05)
        else: self.fail('metadata job exceeded timeout')
        self.send(2, 'gre')
        self.assertEqual(self.read()['items'][0]['text'], 'grep')

    def test_cleanup_before_metadata_pipe_registration(self):
        sys.path.insert(0, str(REPO))
        spec = importlib.util.spec_from_file_location('terminal_worker', REPO / 'terminal-helper.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        worker = module.Worker()
        proc = subprocess.Popen(['/bin/sleep', '30'], stdout=subprocess.PIPE)
        worker.notes_proc = proc
        try:
            worker.stop_notes()
            self.assertIsNotNone(proc.poll())
        finally:
            if proc.poll() is None: proc.kill(); proc.wait()
            worker.selector.close()


if __name__ == '__main__': unittest.main()
