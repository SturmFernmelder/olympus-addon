#!/usr/bin/env python3
"""Brings the honours' finished frames and marks into the addon: Olympus/media/honors/ (1.2).

The frames were finished in the frame lab (the throwaway OlympusFrameLab addon, where each was
seen in game on a portrait and a nameplate) as WoW-ready textures, the format of the addon's other
art (Olympus/media/borders, scripts/make-borders.py): 32-bit uncompressed true colour with an
8-bit alpha channel (TGA type 2), bottom-left origin, the TGA 2.0 footer; a frame on a 256 x 256
canvas with its art at the top left (winged 220 x 180, plain 200 x 200: Borders.lua's texture
coordinates), a nameplate mark on 32 x 32. The lab names each frame <name>.tga (gold; the
Paladin's gold is paladin-new.tga), <name>-silver.tga and <name>-bronze.tga, and each mark
<name>-<metal>-mark.tga.

Only the ones the honours use come in (the design), renamed <name>-<metal>.tga and
<name>-<metal>-mark.tga, the stems Honors.ArtOf gives (the Lua tests check the two lists agree):
the arena champion's gryphon, the nine class beasts, the eight racial mounts, the cornucopia (all
time donors), the koi (the month's donors), the raven (the Oracle) and the comet (the level race),
each in gold, silver and bronze; the best guild's owl in gold alone. The lab's other files (the
raw and colour drafts, the phoenix, the dragon, the owl's silver and bronze) stay out.

1.2.1: the new frames, a preview only (the author's /oly borders test; no honour names them, so
nobody can be awarded or wear them): the Apostles' cross, the Bones' charm and the skyborn's
owlcat in gold, silver and bronze, and the red cross (an Apostle's own look, on his screen alone).
They were finished outside the lab, already in the shipped format and under their shipped names,
in ~/Downloads/olympus-new-frames (the uncut ones at its top, not its cut/ folder), and come in
from there unrenamed (--new).

1.2.3: the missionaries' shepherd's crook with its sleeping lamb in gold, silver and bronze (the
Church's top 3 missionaries, worn: Honors.FRAMES_SHIPPED), finished the same way and brought in
from the same folder (--new; the lab is not needed for it: --new alone keeps the lab's rows of
SHA256SUMS as they are, each checked against the file shipped). So the package carries 80 frames
and 80 marks and nothing else: 80 x 262,188 + 80 x 4,140 bytes = 21,306,240 bytes (20.3 MiB) on
disk, about 3.6 MB in the zip (the transparent canvas packs well). The files are copied byte for
byte, never re-encoded.

Their provenance stays in the repository without a second copy of 20 MB: media/honors/src/SHA256SUMS
(outside the package, like media/borders/src) records each source file's SHA-256, its source name
(the lab's file name, or the new frames' folder and name: ~/Downloads/olympus-new-frames/<name>)
and the addon name it ships as, written by --from (or --new alone). --check compares every shipped
file with it byte for byte (through the hash), so the art can be checked again after the sources
are gone.

Usage, from anywhere (no Pillow needed):
  python3 scripts/make-honors.py --from <lab media folder> [--new <folder>]
                                                             copy and rename them in (the new
                                                             frames from <folder>, by default
                                                             ~/Downloads/olympus-new-frames), and
                                                             write media/honors/src/SHA256SUMS
  python3 scripts/make-honors.py --new <folder>              the new frames alone from <folder>
                                                             (the lab's files as they ship, their
                                                             rows of SHA256SUMS kept), and write it
  python3 scripts/make-honors.py --check                     fail unless the shipped set is whole,
                                                             each file has the right shape and is
                                                             the source file SHA256SUMS records
  python3 scripts/make-honors.py --check --from <folder>     ...and is byte for byte its source
                                 [--new <folder>]            (the lab's; the new frames' with --new)
"""

import hashlib
import os
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUTPUT = os.path.join(ROOT, "Olympus", "media", "honors")
MANIFEST = os.path.join(ROOT, "media", "honors", "src", "SHA256SUMS")

METALS = ("gold", "silver", "bronze")
# Each beast of the honours table, and the metals it comes in.
BEASTS = [
    "gryphon",                                              # the arena champion (winged)
    "boar", "paladin", "hunter", "rogue", "priest",         # the class champions' beasts
    "shaman", "mage", "warlock", "druid",
    "lion", "ram", "nightsaber", "mechanostrider",          # the race champions' mounts
    "orc-wolf", "skeletal-horse", "kodo", "raptor",
    "cornucopia", "koi", "raven", "comet",                  # donors, the month's, the Oracle, the level race
]
GOLD_ONLY = ["owl"]                                          # the best guild's leader (winged)
# The lab's name for a gold frame, where it is not <name>.tga.
GOLD_SOURCE = {"paladin": "paladin-new"}
# 1.2.1, a preview only (Honors.PREVIEWS): from the new frames' folder, under their own names.
NEW_SOURCE = "~/Downloads/olympus-new-frames"
NEW_BEASTS = ["cross", "charm", "owlcat", "crook"]           # the Apostles', the Bones', the skyborn's; 1.2.3 the missionaries'
NEW_ONLY = ["cross-red"]                                     # the Apostles' red cross (one look, no metal)
FRAME_SIZE, MARK_SIZE = 256, 32


def files():
    """(addon file name, source file name, square size, source) for every file the honours ship:
    source "lab" (--from's folder, the lab's name) or "new" (--new's folder, NEW_SOURCE/<name>)."""
    out = []
    for beast in BEASTS + GOLD_ONLY:
        for metal in (METALS if beast in BEASTS else ("gold",)):
            frame = GOLD_SOURCE.get(beast, beast) if metal == "gold" else beast + "-" + metal
            out.append(("%s-%s.tga" % (beast, metal), frame + ".tga", FRAME_SIZE, "lab"))
            out.append(("%s-%s-mark.tga" % (beast, metal), "%s-%s-mark.tga" % (beast, metal), MARK_SIZE, "lab"))
    stems = ["%s-%s" % (beast, metal) for beast in NEW_BEASTS for metal in METALS] + NEW_ONLY
    for stem in stems:
        for name, size in ((stem + ".tga", FRAME_SIZE), (stem + "-mark.tga", MARK_SIZE)):
            out.append((name, NEW_SOURCE + "/" + name, size, "new"))
    return out


def shape_error(data, size):
    """Why the bytes are not a size x size 32-bit uncompressed TGA with alpha, or None."""
    if len(data) != 18 + size * size * 4 + 26:
        return "%d bytes, not %d" % (len(data), 18 + size * size * 4 + 26)
    idlen, cmap, kind, _, _, _, _, _, width, height, bits, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if (idlen, cmap, kind, width, height, bits, desc) != (0, 0, 2, size, size, 32, 8):
        return "header %r" % ((idlen, cmap, kind, width, height, bits, desc),)
    if not data.endswith(b"TRUEVISION-XFILE.\0"):
        return "no TGA 2.0 footer"
    return None


def read(path):
    with open(path, "rb") as f:
        return f.read()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_manifest():
    """{ addon name: (sha256, lab name) } from SHA256SUMS, or None when it is missing."""
    if not os.path.exists(MANIFEST):
        return None
    out = {}
    with open(MANIFEST, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            digest, lab, name = line.split()
            out[name] = (digest, lab)
    return out


def write_manifest(rows):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        f.write("# The honours' art (Olympus/media/honors): each file's SHA-256, the frame lab's file it was\n")
        f.write("# copied from, and its name in the addon. Written by scripts/make-honors.py --from; checked by --check.\n")
        f.write("# 1.2.1's new frames and 1.2.3's crook name their source as ~/Downloads/olympus-new-frames/<name>.\n")
        for name, lab, digest in sorted(rows):
            f.write("%s  %s  %s\n" % (digest, lab, name))


def folder(argv, flag, what):
    if flag not in argv:
        return None
    i = argv.index(flag)
    if i + 1 >= len(argv):
        sys.exit("%s needs %s" % (flag, what))
    return argv[i + 1]


def main(argv):
    check = "--check" in argv
    source = folder(argv, "--from", "the lab's media folder")
    new = folder(argv, "--new", "the new frames' folder")
    if not check and not source and not new:
        sys.exit(__doc__)
    if not check and not new:
        new = os.path.expanduser(NEW_SOURCE)
    sources = {"lab": source, "new": new}
    wanted = files()
    problems = []
    # (--new alone, 1.2.3: the lab's files stay as they ship, their rows read from SHA256SUMS.)
    manifest = read_manifest() if check or not source else None
    if manifest is None and (check or not source):
        problems.append("missing: media/honors/src/SHA256SUMS")
    rows = []
    if not check:
        os.makedirs(OUTPUT, exist_ok=True)
    for name, lab, size, kind in wanted:
        target = os.path.join(OUTPUT, name)
        data = None
        if sources[kind]:
            path = os.path.join(sources[kind], os.path.basename(lab))
            if not os.path.exists(path):
                problems.append("missing in the source: " + lab)
                continue
            data = read(path)
            why = shape_error(data, size)
            if why:
                problems.append("%s: %s" % (lab, why))
                continue
        if check:
            if not os.path.exists(target):
                problems.append("missing: Olympus/media/honors/" + name)
                continue
            shipped = read(target)
            why = shape_error(shipped, size)
            recorded = manifest.get(name) if manifest is not None else None
            if why:
                problems.append("%s: %s" % (name, why))
            elif data is not None and shipped != data:
                problems.append("%s is not %s" % (name, lab))
            elif manifest is None:
                pass
            elif not recorded or recorded[1] != lab:
                problems.append("%s: not in media/honors/src/SHA256SUMS as %s" % (name, lab))
            elif recorded[0] != sha(shipped):
                problems.append("%s is not the lab's %s (SHA256SUMS)" % (name, lab))
        elif data is None:
            # (--new alone) a lab file as it ships: its row kept when the file is still the one it names.
            recorded = manifest.get(name) if manifest is not None else None
            if not os.path.exists(target):
                problems.append("missing: Olympus/media/honors/%s (bring the lab's files in with --from)" % name)
            elif not recorded or recorded[1] != lab or recorded[0] != sha(read(target)):
                problems.append("%s is not the lab's %s (SHA256SUMS): bring the lab's files in with --from" % (name, lab))
            else:
                rows.append((name, lab, recorded[0]))
        else:
            with open(target, "wb") as f:
                f.write(data)
            rows.append((name, lab, sha(data)))
    names = set(n for n, _, _, _ in wanted)
    if os.path.isdir(OUTPUT):
        for extra in sorted(os.listdir(OUTPUT)):
            if extra.endswith(".tga") and extra not in names:
                problems.append("not an honour's file: Olympus/media/honors/" + extra)
    for extra in sorted(set(manifest or {}) - names):
        problems.append("SHA256SUMS names a file the honours do not ship: " + extra)
    if problems:
        sys.exit("\n".join(problems))
    if not check:
        write_manifest(rows)
    total = sum(os.path.getsize(os.path.join(OUTPUT, n)) for n in names)
    print("%s %d honour files (%d frames, %d marks), %d bytes" % ("checked" if check else "wrote", len(names),
          len(names) // 2, len(names) // 2, total))


if __name__ == "__main__":
    main(sys.argv[1:])
