#!/bin/bash
# Pywal formats templates with Python str.format; literal braces must double.
set -euo pipefail
python3 - "$(dirname "${BASH_SOURCE[0]}")/templates" <<'PY'
from pathlib import Path
from string import Formatter
import sys

class Color(str):
    @property
    def strip(self):
        return self.lstrip('#')

colors = {f'color{i}': Color('#112233') for i in range(16)}
colors.update({key: Color('#112233') for key in ('foreground', 'background', 'cursor')})
colors.update(wallpaper='/fixture/wallpaper.jpg', alpha='100')
templates = list(Path(sys.argv[1]).iterdir())
assert templates, 'No pywal templates found'
for template in templates:
    if template.is_file():
        text = template.read_text()
        list(Formatter().parse(text))
        rendered = text.format(**colors)
        if template.suffix == '.lua':
            assert rendered.startswith('return {\n') and rendered.rstrip().endswith('}')
            assert 'rgba(112233CC)' in rendered
        print(f'ok: {template.name} renders without format errors')
PY
