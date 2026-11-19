#!/bin/bash
# Interrupt before and after the real atomic keeper publication.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
sandboxed /usr/bin/python3 - "$repo/overlay-publish.py" "$sandbox" <<'PY'
import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location('publish', sys.argv[1])
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
root = Path(sys.argv[2])
class Interrupted(BaseException): pass

def pair(name):
    live, staged = root / (name+'-live'), root / (name+'-staged')
    for directory, version in [(live,'old'),(staged,'new')]:
        directory.mkdir()
        (directory/'overlay-clones.sh').write_text(version)
        (directory/'i18n').mkdir()
        (directory/'i18n'/'catalog').write_text(version)
    return staged, live

def intact(live, version):
    assert (live/'overlay-clones.sh').read_text() == version
    assert (live/'i18n'/'catalog').read_text() == version

staged,live=pair('before')
exchange=p.exchange
p.exchange=lambda *_: (_ for _ in ()).throw(Interrupted())
try: p.publish_keeper(staged,live)
except Interrupted: pass
else: raise AssertionError('did not interrupt before exchange')
intact(live,'old')
print('ok - interruption before publication keeps the complete old keeper')

staged,live=pair('after')
def interrupt_after(*args):
    exchange(*args)
    raise Interrupted()
p.exchange=interrupt_after
try: p.publish_keeper(staged,live)
except Interrupted: pass
else: raise AssertionError('did not interrupt after exchange')
intact(live,'new');intact(staged,'old')
print('ok - interruption after publication keeps the complete new keeper')

p.exchange=exchange
staged,live=pair('success')
p.publish_keeper(staged,live)
intact(live,'new');assert not staged.exists()
print('ok - completed refresh removes only the replaced copy')

staged=root/'initial-staged';staged.mkdir()
(staged/'overlay-clones.sh').write_text('new')
live=root/'initial-live'
p.publish_keeper(staged,live)
assert (live/'overlay-clones.sh').read_text()=='new'
print('ok - first keeper publication uses an atomic move')

staged,live=pair('unsupported')
p.exchange=lambda *_: (_ for _ in ()).throw(OSError('unsupported'))
try: p.publish_keeper(staged,live)
except OSError: pass
else: raise AssertionError('expected unsupported exchange to fail')
intact(live,'old')
print('ok - unsupported exchange fails without removing the keeper')
PY
[[ $? == 0 ]] || failed=1
finish
