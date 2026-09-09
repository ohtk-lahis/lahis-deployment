"""Compile the deliberately small probe Markdown subset, fail on unknown syntax.

Output is a model for native Google Docs primitives, not DOCX. Image references
resolve from the existing guide on each run; never persist expiring content URIs.
"""
import json
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
blocks = []
for line in source.read_text().splitlines():
    if not line.strip():
        continue
    if line.startswith('|'):
        if re.match(r'^\|[-:| ]+\|$', line):
            continue
        cells = [x.strip().replace('\\|', '|') for x in re.split(r'(?<!\\)\|', line.strip('|'))]
        if not blocks or blocks[-1]['kind'] != 'table':
            blocks.append({'kind': 'table', 'rows': []})
        blocks[-1]['rows'].append(cells)
        continue
    image = re.fullmatch(r'!\[([^]]+)\]\(drive-image:([^)]+)\)', line)
    ordered = re.match(r'^(\d+)\. (.+)$', line)
    if image:
        blocks.append({'kind': 'image', 'alt': image[1], 'imageId': image[2]})
    elif line.startswith('# '):
        blocks.append({'kind': 'title', 'text': line[2:]})
    elif line.startswith('## '):
        blocks.append({'kind': 'heading', 'text': line[3:]})
    elif ordered:
        if int(ordered[1]) == 1 or not blocks or blocks[-1]['kind'] != 'number':
            group = len(blocks)
        blocks.append({'kind': 'number', 'text': ordered[2], 'group': group})
    elif line.startswith('- '):
        blocks.append({'kind': 'bullet', 'text': line[2:]})
    elif line.startswith('*') and line.endswith('*'):
        blocks.append({'kind': 'caption', 'text': line[1:-1]})
    elif line.startswith(('#', '!', '>', '`', '<')):
        raise ValueError('Unsupported probe syntax: ' + line)
    else:
        blocks.append({'kind': 'body', 'text': line})
for b in blocks:
    if b['kind'] == 'table':
        assert len({len(r) for r in b['rows']}) == 1
print(json.dumps({'font': 'Sarabun', 'fontNote': 'Google Docs font library name; not TH Sarabun New',
                  'bodyPt': 16, 'sourceDocument': '1fQ5PPBGFqQBeDZBfwNpIxYhvlCGDEjS1WU_erig-j_o',
                  'blocks': blocks}, ensure_ascii=False))
