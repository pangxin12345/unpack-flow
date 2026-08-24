#!/usr/bin/env python3
"""Normalize staged release text while preserving native tool bytes."""
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in root.rglob('*'):
    if not path.is_file():
        continue
    relative = path.relative_to(root)
    in_tools = 'tools' in relative.parts
    # Only reviewed textual metadata below tools/ may be normalized. Every
    # executable, library, native tool and bundled archive is skipped.
    if in_tools and path.suffix.lower() != '.txt':
        continue
    data = path.read_bytes()
    if b'\0' in data:
        continue
    normalized = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    if normalized != data:
        path.write_bytes(normalized)
