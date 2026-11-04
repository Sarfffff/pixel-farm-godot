"""Validate resource paths and directory boundaries without starting Godot.

Run from any directory: python tools/maintenance/audit_project_layout.py
--repair-legacy-paths only updates known old path strings; it never moves files.
--report PATH saves a machine-readable audit. No player data is accessed.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT_TYPES = {'.gd', '.tscn', '.tres', '.godot', '.cfg', '.json', '.ps1', '.md', '.import'}
RESOURCE_TYPES = {'.gd', '.tscn', '.tres', '.png', '.svg', '.wav', '.ogg', '.json', '.gdshader'}
RESOURCE_PATH = re.compile(r'["\'](res://[^"\'\n]+)["\']')
RUNTIME_DIRS = ('scripts', 'scenes', 'data', 'assets')


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def files_in(folders: tuple[str, ...]):
    for folder in folders:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and path.suffix in TEXT_TYPES:
                yield path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repair-legacy-paths', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    migration = json.loads((Path(__file__).with_name('path_migrations.json')).read_text(encoding='utf-8'))
    replacements = {item['from']: item['to'] for item in migration['paths']}
    pattern = re.compile('|'.join(re.escape(p) for p in sorted(replacements, key=len, reverse=True)))
    errors: list[str] = []
    repaired: list[str] = []
    inspected = 0
    literal_refs = 0
    for path in list(files_in(RUNTIME_DIRS + ('tools',))) + [ROOT / 'project.godot', ROOT / 'export_presets.cfg']:
        if path.name == 'path_migrations.json' or path.suffix == '.md' or path == Path(__file__).resolve():
            continue
        text = path.read_text(encoding='utf-8-sig')
        inspected += 1
        if args.repair_legacy_paths:
            updated = pattern.sub(lambda match: replacements[match[0]], text)
            if updated != text:
                path.write_bytes(updated.encode('utf-8'))
                repaired.append(relative(path))
                text = updated
        old = pattern.search(text)
        if old:
            errors.append(f'{relative(path)}: legacy path {old[0]}')
        is_runtime = path.parts[len(ROOT.parts)] in RUNTIME_DIRS
        # Tool strings include future output filenames; runtime resources may not.
        if is_runtime and path.suffix in {'.gd', '.tscn', '.tres', '.json'}:
            for match in RESOURCE_PATH.finditer(text):
                address = match[1][6:]
                if '%' in address or '*' in address or '{' in address:
                    continue
                literal_refs += 1
                target = ROOT / address
                if path.suffix != '.json' and address.startswith(('art/', 'archive/', 'tools/', 'build/')):
                    errors.append(f'{relative(path)}: runtime depends on excluded {address}')
                if Path(address).suffix in RESOURCE_TYPES and not target.exists():
                    # Catalog descriptions can retain planned output paths only in raw sources.
                    errors.append(f'{relative(path)}: missing {address}')

    for folder in ('art', 'archive', 'build'):
        if not (ROOT / folder / '.gdignore').is_file():
            errors.append(f'{folder}/.gdignore is missing')
    for old in ('assets/generated', 'assets/game', 'scripts/systems', '星露谷物语素材'):
        if (ROOT / old).exists():
            errors.append(f'legacy directory reappeared: {old}')
    for folder in ('scripts/world', 'scripts/ui', 'tools'):
        if list((ROOT / folder).glob('*.gd')):
            errors.append(f'{folder}: scripts must live in a responsibility subdirectory')
    for readme in ('art/README.md', 'assets/README.md', 'scripts/README.md', 'tools/README.md'):
        if not (ROOT / readme).is_file():
            errors.append(f'missing directory guide: {readme}')
    preset = (ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
    excluded = re.search(r'^exclude_filter="([^"]*)"', preset, re.MULTILINE)
    for folder in ('art', 'archive', 'tools', 'docs', 'build'):
        if not excluded or folder + '/*' not in excluded[1]:
            errors.append(f'export must exclude {folder}/*')

    uids: dict[str, str] = {}
    for folder in ('scripts', 'tools'):
        for path in sorted((ROOT / folder).rglob('*.gd.uid')):
            uid = path.read_text(encoding='utf-8').strip()
            if uid in uids:
                errors.append(f'duplicate script UID: {relative(path)} and {uids[uid]}')
            uids[uid] = relative(path)
    stats = {folder: sum(p.is_file() and p.suffix not in {'.import', '.uid'} for p in (ROOT / folder).rglob('*'))
             for folder in ('art', 'assets', 'scripts', 'scenes', 'data', 'tools')}
    report = {'passed': not errors, 'text_files_checked': inspected, 'literal_resource_paths_checked': literal_refs,
              'script_uids_checked': len(uids), 'files_by_area_without_sidecars': stats,
              'repaired_files': repaired, 'errors': errors}
    if args.report:
        target = args.report if args.report.is_absolute() else ROOT / args.report
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"[layout] {'PASS' if not errors else 'FAIL'}: {inspected} text files, {literal_refs} paths, {len(uids)} script UIDs, {len(errors)} errors; {len(repaired)} repaired")
    for error in errors[:40]:
        print('  ' + error)
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
