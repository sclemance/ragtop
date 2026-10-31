#!/usr/bin/python3
"""Compare a git revision's key renderer with the working tree, in isolation.

Requires Qt6 Quick development files, c++, dbus-run-session and (visual mode)
Pillow. Uses the GPU via offscreen OpenGL; no session input or settings access.
Run from a graphical session. Artifacts live in a unique temporary directory.
"""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SOURCES = ['KeyboardKey.qml', 'KeyboardTheme.qml', 'KeyIcon.qml', 'KeyContrast.js',
           'SculptedKeycap.qml', 'KeyGlow.qml', 'GlowRipple.qml', 'GlowWave.js', 'GlowColors.js']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, help='baseline git revision')
    parser.add_argument('--mode', choices=['visual', 'timing', 'both'], default='both')
    args = parser.parse_args()
    reference = subprocess.check_output(['git', 'rev-parse', '--verify', args.reference + '^{commit}'],
                                        cwd=REPO, text=True).strip()
    run = Path(tempfile.mkdtemp(prefix='ragtop-render-'))
    print('Artifacts:', run, flush=True)
    for variant in ['before', 'after']:
        dest = run / variant
        dest.mkdir()
        shutil.copytree(HERE / 'imports', dest / 'imports')
        for name in ['bench.qml', 'capture.qml']:
            shutil.copy(HERE / name, dest / name)
        for name in SOURCES:
            data = (subprocess.check_output(['git', 'show', reference + ':' + name], cwd=REPO)
                    if variant == 'before' else (REPO / name).read_bytes())
            (dest / name).write_bytes(data)
    env = dict(PATH='/usr/bin:/bin', LANG='C.UTF-8', QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl')
    for key in ['DISPLAY', 'XAUTHORITY']:
        if key in os.environ: env[key] = os.environ[key]
    for key in ['HOME', 'XDG_RUNTIME_DIR', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME']:
        d = run / key
        d.mkdir(mode=0o700)
        env[key] = str(d)
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Quick', 'Qt6Gui', 'Qt6Qml'], text=True).split()
    names = ['bench', 'capture'] if args.mode == 'both' else ['capture' if args.mode == 'visual' else 'bench']
    for name in names:
        subprocess.run(['c++', '-std=c++17', '-O2', '-fPIC', str(HERE / (name + '.cpp')),
                        '-o', str(run / name), *flags], check=True)
    if args.mode in ('both', 'timing'):
        for trial, variant in enumerate(['before', 'after', 'before', 'after']):
            prefix = str(trial) + '-' + variant
            with (run / (prefix + '.jsonl')).open('w') as out, (run / (prefix + '.log')).open('w') as err:
                subprocess.run(['dbus-run-session', '--', str(run / 'bench'), str(run / variant)],
                               env=env, stdout=out, stderr=err, check=True, timeout=90)
            print(prefix, (run / (prefix + '.jsonl')).read_text(), flush=True)
    if args.mode in ('both', 'visual'):
        from PIL import Image, ImageChops
        results = []
        for scale in ['1', '1.25']:
            env['QT_SCALE_FACTOR'] = scale
            for variant in ['before', 'after']:
                dest = run / (variant + '-' + scale)
                with (run / (variant + '-' + scale + '.log')).open('w') as err:
                    subprocess.run(['dbus-run-session', '--', str(run / 'capture'),
                                    str(run / variant), str(dest)], env=env, stderr=err, check=True, timeout=180)
            for n in range(16):
                a = Image.open(run / ('before-' + scale) / (str(n) + '.png')).convert('RGB')
                b = Image.open(run / ('after-' + scale) / (str(n) + '.png')).convert('RGB')
                diff = ImageChops.difference(a, b)
                same = a.size == b.size and diff.getbbox() is None
                results.append({'scale': scale, 'case': n, 'identical': same})
                if not same: diff.save(run / ('diff-' + scale + '-' + str(n) + '.png'))
        (run / 'visual-results.json').write_text(json.dumps(results, indent=2))
        print('Identical:', sum(r['identical'] for r in results), '/', len(results))
        if not all(r['identical'] for r in results): raise SystemExit(1)


if __name__ == '__main__': main()
