#!/usr/bin/env python3
"""
Generates the Duplicate Finder control fixture set.

Deterministic: the same seed always produces the same files, contents, names and
modification dates, so results can be compared across revisions of the app.

    python3 Scripts/make_fixtures.py            # writes Fixtures/Control
    python3 Scripts/make_fixtures.py --out DIR

Layout (meant to be dropped into the app in this priority order):
    Control/Primary    originals (plus a few in-folder copies)
    Control/Backup     mostly byte-for-byte copies (cp, original dates kept)
    Control/Downloads  mostly re-written copies (new file, same content, newer date)
    Control/Archive    deeply nested copies
    Control/EdgeCases  things that must NOT be reported as duplicates

Fixtures/manifest.json lists every expected duplicate group and the edge cases.
"""
import argparse, hashlib, json, os, random, shutil, time
from pathlib import Path

SEED = 20261108
ORIGINAL_COUNT = 50
DUPLICATE_COUNT = 30
BASE_TIME = time.mktime((2025, 1, 1, 9, 0, 0, 0, 0, -1))
DAY = 86400

WORDS = """alpha beacon cobalt drift ember falcon glacier harbor indigo juniper kestrel lantern
meadow nebula orchard pixel quartz ripple summit tundra umber velvet willow xenon yonder zephyr
anchor bramble canyon delta echo fjord garnet hollow iris jasper kelp lagoon mosaic nimbus onyx
prairie quill raven sable thistle uplift vortex wren yarrow zenith copper silver amber cedar maple
river stone cloud ocean forest desert island valley signal vector buffer cache thread kernel""".split()

rng = random.Random(SEED)

def words(n): return " ".join(rng.choice(WORDS) for _ in range(n))
def sentence(): s = words(rng.randint(6, 14)); return s[0].upper() + s[1:] + "."
def paragraph(): return " ".join(sentence() for _ in range(rng.randint(3, 7)))
def ident(): return rng.choice(WORDS) + rng.choice(WORDS).capitalize()

def gen_txt():
    return "\n\n".join(paragraph() for _ in range(rng.randint(2, 6))) + "\n"

def gen_md():
    out = [f"# {words(3).title()}", "", paragraph(), ""]
    for _ in range(rng.randint(1, 3)):
        out += [f"## {words(2).title()}", ""]
        out += [f"- {sentence()}" for _ in range(rng.randint(2, 5))]
        out += ["", paragraph(), ""]
    return "\n".join(out)

def gen_json():
    data = {
        "id": rng.randint(1000, 9999),
        "name": words(2),
        "enabled": rng.choice([True, False]),
        "tags": [rng.choice(WORDS) for _ in range(rng.randint(1, 5))],
        "items": [{"key": ident(), "value": rng.randint(0, 500)} for _ in range(rng.randint(2, 8))],
    }
    return json.dumps(data, indent=2) + "\n"

def gen_yml():
    out = [f"name: {ident()}", f"version: {rng.randint(1,9)}.{rng.randint(0,20)}.{rng.randint(0,9)}", "services:"]
    for _ in range(rng.randint(1, 4)):
        out += [f"  {rng.choice(WORDS)}:", f"    image: {rng.choice(WORDS)}:{rng.randint(1,20)}",
                f"    port: {rng.randint(3000, 9000)}", f"    replicas: {rng.randint(1, 5)}"]
    return "\n".join(out) + "\n"

def gen_swift():
    t = ident().capitalize()
    props = "\n".join(f"  var {ident()}: Int = {rng.randint(0, 99)}" for _ in range(rng.randint(2, 5)))
    return f"import Foundation\n\n/// {sentence()}\nstruct {t} {{\n{props}\n\n  func {ident()}() -> String {{\n    \"{words(4)}\"\n  }}\n}}\n"

def gen_py():
    f = ident()
    return f'"""{sentence()}"""\n\n\ndef {f}(values):\n    total = 0\n    for v in values:\n        total += v * {rng.randint(2, 9)}\n    return total\n\n\nif __name__ == "__main__":\n    print({f}([{", ".join(str(rng.randint(0, 50)) for _ in range(5))}]))\n'

def gen_js():
    f = ident()
    return f"// {sentence()}\nexport function {f}(input) {{\n  const words = {json.dumps([rng.choice(WORDS) for _ in range(4)])};\n  return words.map((w) => `${{w}}-${{input}}`);\n}}\n"

def gen_csv():
    rows = ["id,name,score,active"]
    rows += [f"{i},{rng.choice(WORDS)},{rng.randint(0,100)},{rng.choice(['true','false'])}" for i in range(rng.randint(5, 25))]
    return "\n".join(rows) + "\n"

def gen_html():
    return f"<!doctype html>\n<html>\n<head><title>{words(2).title()}</title></head>\n<body>\n  <h1>{words(3).title()}</h1>\n  <p>{paragraph()}</p>\n</body>\n</html>\n"

GENERATORS = {"txt": gen_txt, "md": gen_md, "json": gen_json, "yml": gen_yml, "swift": gen_swift,
              "py": gen_py, "js": gen_js, "csv": gen_csv, "html": gen_html}

def sha256(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def write(path, content, mtime):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content) if isinstance(content, str) else path.write_bytes(content)
    os.utime(path, (mtime, mtime))

def main():
    ap = argparse.ArgumentParser()
    root_dir = Path(__file__).resolve().parent.parent / "Fixtures"
    ap.add_argument("--out", type=Path, default=root_dir)
    out = ap.parse_args().out
    control = out / "Control"
    if control.exists(): shutil.rmtree(control)

    primary_subdirs = ["", "", "Notes", "Projects/Web", "Projects/Scripts", "Config"]
    exts = list(GENERATORS)

    # --- Originals -------------------------------------------------------------
    originals, used = [], set()
    for i in range(ORIGINAL_COUNT):
        ext = exts[i % len(exts)]
        while True:
            name = f"{rng.choice(WORDS)}-{rng.choice(WORDS)}.{ext}"
            if name not in used: used.add(name); break
        path = control / "Primary" / rng.choice(primary_subdirs) / name
        write(path, GENERATORS[ext](), BASE_TIME + i * DAY)
        originals.append(path)

    # --- Duplicates ------------------------------------------------------------
    # Pick ~18 originals; some get several copies so groups of 2, 3 and 4 exist.
    sources = rng.sample(originals, 18)
    copy_counts = [1] * 18
    for _ in range(DUPLICATE_COUNT - 18):
        copy_counts[rng.randrange(18)] += 1

    plans = [  # (folder, method) choices
        ("Backup", "cp"), ("Backup/2025", "cp"), ("Downloads", "rewrite"),
        ("Archive/Old/Nested", "cp"), ("Archive/Old", "rewrite"), ("Primary", "in-folder"),
    ]
    duplicates = []
    for src, count in zip(sources, copy_counts):
        for n in range(count):
            folder, method = rng.choice(plans)
            stem, ext = src.stem, src.suffix
            if method == "in-folder":
                # Copy inside the same Primary folder with a Finder-style name (tiebreak test).
                dest = src.with_name(f"{stem} copy{'' if n == 0 else ' ' + str(n + 1)}{ext}")
                method = "cp"
            else:
                name = rng.choice([src.name, f"{stem} (1){ext}", f"{stem}-final{ext}", f"{rng.choice(WORDS)}{ext}"])
                # Occasionally change the extension: same bytes are still an exact duplicate.
                if method == "rewrite" and rng.random() < 0.2:
                    name = Path(name).stem + ".txt"
                dest = control / folder / name
            while dest.exists():
                dest = dest.with_name(f"{dest.stem}-{rng.randint(10, 99)}{dest.suffix}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            if method == "cp":
                shutil.copy2(src, dest)  # byte copy, keeps original dates
            else:
                write(dest, src.read_bytes(), src.stat().st_mtime + rng.randint(5, 200) * DAY)
            duplicates.append({"path": str(dest.relative_to(out)), "source": str(src.relative_to(out)), "method": method})

    # --- Edge cases (none of these are duplicates) ------------------------------
    edge = control / "EdgeCases"
    edge_notes = []
    base = gen_txt()
    write(edge / "near-dup-a.txt", base, BASE_TIME)
    write(edge / "near-dup-b.txt", base[:-2] + ("X" if base[-2] != "X" else "Y") + base[-1], BASE_TIME)
    edge_notes.append("near-dup-a/b.txt: same size, differ by one byte near the end")

    s1 = "a" * 512; s2 = "b" * 512
    write(edge / "same-size-1.txt", s1, BASE_TIME); write(edge / "same-size-2.txt", s2, BASE_TIME)
    edge_notes.append("same-size-1/2.txt: identical size, different content")

    head = ("".join(gen_txt() for _ in range(400)))[:200_000]
    write(edge / "large-same-prefix-1.txt", head + "TAIL-ONE\n", BASE_TIME)
    write(edge / "large-same-prefix-2.txt", head + "TAIL-TWO\n", BASE_TIME)
    edge_notes.append("large-same-prefix-1/2.txt: ~200 KB, same size and first 200 KB, different tail (defeats prefix-only hashing)")

    write(edge / "empty-1.txt", "", BASE_TIME); write(edge / "empty-2.md", "", BASE_TIME)
    edge_notes.append("empty-1.txt / empty-2.md: zero-byte files, should be skipped")

    link_target = originals[0]
    (edge / "symlink-to-original").symlink_to(os.path.relpath(link_target, edge))
    os.utime(edge / "symlink-to-original", (BASE_TIME, BASE_TIME), follow_symlinks=False)
    edge_notes.append(f"symlink-to-original: symlink to {link_target.relative_to(out)}, should be skipped")

    # --- Manifest ----------------------------------------------------------------
    groups = {}
    for d in duplicates:
        groups.setdefault(d["source"], []).append(d)
    manifest = {
        "seed": SEED,
        "summary": {
            "originals": len(originals),
            "duplicates": len(duplicates),
            "duplicate_groups": len(groups),
            "total_files_in_groups": len(groups) + len(duplicates),
        },
        "groups": [
            {"sha256": sha256(out / src), "size": (out / src).stat().st_size,
             "original": src, "copies": [{"path": c["path"], "method": c["method"]} for c in copies]}
            for src, copies in sorted(groups.items())
        ],
        "edge_cases": edge_notes,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    s = manifest["summary"]
    print(f"Wrote {s['originals']} originals and {s['duplicates']} duplicates "
          f"({s['duplicate_groups']} groups) to {control}")

if __name__ == "__main__":
    main()
