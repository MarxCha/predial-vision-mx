"""Relax strict version pins in RV metadata so pkg_resources doesn't complain."""
import glob
import re

paths = glob.glob('/usr/local/lib/python3.6/site-packages/rastervision-*.dist-info/METADATA') + \
        glob.glob('/usr/local/lib/python3.6/site-packages/rastervision-*.egg-info/PKG-INFO')

for meta in paths:
    with open(meta) as f:
        content = f.read()
    # Relax all ==X.Y.* pins to remove version constraint
    content = re.sub(r'(Requires-Dist: \w+)==[\d.*]+', r'\1', content)
    with open(meta, 'w') as f:
        f.write(content)
    print(f'Relaxed pins in {meta}')

if not paths:
    print('No metadata files found, nothing to patch')
