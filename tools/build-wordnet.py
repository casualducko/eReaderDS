#!/usr/bin/env python3
"""Build the bundled English dictionary (StarDict format) from WordNet 3.1.

    tools/build-wordnet.py path/to/wordnet/dict app/dict/wordnet

Reads WordNet's database files (data.*, index.*, *.exc) and writes
wordnet.ifo, wordnet.idx, wordnet.syn and wordnet.dict.dz (dictzip). Each
entry is a little HTML: the word's senses grouped by part of speech, most
common first, each with its definition, one example and a few synonyms.
Irregular forms ("ran", "mice") go in the .syn file, pointing at their base
word. WordNet's license (it must travel with the data) is copied alongside.
"""
import os
import struct
import sys
import zlib
from html import escape

POS = [("n", "noun"), ("v", "verb"), ("a", "adj"), ("r", "adv")]
POS_NAME = {"n": "noun", "v": "verb", "a": "adjective", "s": "adjective", "r": "adverb"}
MAX_SENSES = 12          # per part of speech; the rest are rare senses
MAX_SYNONYMS = 4

LICENSE_HEAD = """WordNet 3.1, from Princeton University (https://wordnet.princeton.edu),
converted to StarDict format for eReaderDS by tools/build-wordnet.py.

"""


def clean_word(w):
    w = w.replace("_", " ")
    # Adjective position markers: "galore(ip)".
    if w.endswith(")") and "(" in w:
        w = w[: w.rindex("(")]
    return w


def read_data(path, pos_letter):
    synsets = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("  "):
                continue
            head, _, gloss = line.partition(" | ")
            parts = head.split()
            offset, ss_type = parts[0], parts[2]
            n = int(parts[3], 16)
            words = [clean_word(parts[4 + 2 * i]) for i in range(n)]
            gloss = gloss.strip()
            # "definition; "example one"; "example two""
            defn, examples = gloss, []
            if '"' in gloss:
                i = gloss.index('"')
                defn = gloss[:i].rstrip("; ").strip()
                for ex in gloss[i:].split('";'):
                    ex = ex.strip().strip(";").strip().strip('"').strip()
                    if ex:
                        examples.append(ex)
            synsets[offset] = {"pos": ss_type, "words": words, "def": defn, "examples": examples}
    return synsets


def read_index(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("  "):
                continue
            p = line.split()
            lemma = p[0].replace("_", " ")
            synset_cnt = int(p[2])
            ptr_cnt = int(p[3])
            offsets = p[4 + ptr_cnt + 2: 4 + ptr_cnt + 2 + synset_cnt]
            out.append((lemma, offsets))
    return out


def stardict_key(word):
    b = word.encode("utf-8")
    return (b.lower(), b)      # g_ascii_strcasecmp, then strcmp


def dictzip(data, out_path, chunk=58315):
    chunks = [data[i:i + chunk] for i in range(0, len(data), chunk)] or [b""]
    comp, sizes = [], []
    for k, c in enumerate(chunks):
        z = zlib.compressobj(9, zlib.DEFLATED, -15)
        # A full flush resets the compressor at each boundary, so every chunk
        # can be inflated on its own (that's what makes dictzip seekable).
        blob = z.compress(c) + z.flush(zlib.Z_FINISH if k == len(chunks) - 1 else zlib.Z_FULL_FLUSH)
        comp.append(blob)
        sizes.append(len(blob))
    assert all(s < 65536 for s in sizes)
    extra_body = struct.pack("<HHH", 1, chunk, len(chunks)) + b"".join(struct.pack("<H", s) for s in sizes)
    extra = b"RA" + struct.pack("<H", len(extra_body)) + extra_body
    header = b"\x1f\x8b\x08" + bytes([0x04]) + b"\x00\x00\x00\x00" + b"\x02\x03" + struct.pack("<H", len(extra)) + extra
    with open(out_path, "wb") as f:
        f.write(header)
        for blob in comp:
            f.write(blob)
        f.write(struct.pack("<II", zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF))


def main():
    src, out = sys.argv[1], sys.argv[2]
    synsets = {}
    for letter, name in POS:
        synsets[letter] = read_data(os.path.join(src, "data." + name), letter)

    # word -> {pos: [offsets in frequency order]}
    senses = {}
    for letter, name in POS:
        for lemma, offsets in read_index(os.path.join(src, "index." + name)):
            senses.setdefault(lemma, {})[letter] = offsets

    entries = {}
    for lemma, by_pos in senses.items():
        html = []
        for letter, _ in POS:
            offs = by_pos.get(letter)
            if not offs:
                continue
            html.append("<p><i>%s</i></p>" % POS_NAME[letter])
            for k, off in enumerate(offs[:MAX_SENSES], 1):
                ss = synsets[letter][off]
                line = "%d. %s" % (k, escape(ss["def"]))
                if ss["examples"]:
                    line += " <i>“%s”</i>" % escape(ss["examples"][0])
                syn = [w for w in ss["words"] if w.lower() != lemma][:MAX_SYNONYMS]
                if syn:
                    line += " (%s)" % escape(", ".join(syn))
                html.append("<p>%s</p>" % line)
        entries[lemma] = "".join(html)

    words = sorted(entries, key=stardict_key)
    index_of = {}
    dict_data = bytearray()
    idx = bytearray()
    for i, w in enumerate(words):
        body = entries[w].encode("utf-8")
        idx += w.encode("utf-8") + b"\0" + struct.pack(">II", len(dict_data), len(body))
        dict_data += body
        index_of[w] = i

    # Irregular forms: "ran run", "geese goose".
    syn = []
    for letter, name in POS:
        path = os.path.join(src, name + ".exc")
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.split()
                if len(p) < 2:
                    continue
                form = p[0].replace("_", " ")
                for base in p[1:]:
                    base = base.replace("_", " ")
                    if base in index_of and form not in index_of:
                        syn.append((form, index_of[base]))
                        break
    syn = sorted(set(syn), key=lambda t: stardict_key(t[0]))
    syn_data = b"".join(w.encode("utf-8") + b"\0" + struct.pack(">I", i) for w, i in syn)

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out + ".idx", "wb") as f:
        f.write(idx)
    with open(out + ".syn", "wb") as f:
        f.write(syn_data)
    dictzip(bytes(dict_data), out + ".dict.dz")
    with open(out + ".ifo", "w", encoding="utf-8") as f:
        f.write("StarDict's dict ifo file\nversion=2.4.2\n")
        f.write("bookname=WordNet (English)\n")
        f.write("wordcount=%d\nsynwordcount=%d\nidxfilesize=%d\n" % (len(words), len(syn), len(idx)))
        f.write("sametypesequence=h\n")
        f.write("website=https://wordnet.princeton.edu\n")
        f.write("description=WordNet 3.1 Copyright 2011 by Princeton University. See WordNet-LICENSE.txt.\n")
    with open(os.path.join(os.path.dirname(out), "WordNet-LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(LICENSE_HEAD)
        with open(os.path.join(src, "data.noun"), encoding="utf-8", errors="replace") as d:
            for line in d:
                if not line.startswith("  "):
                    break
                f.write(line.strip().split(" ", 1)[1].strip() + "\n" if " " in line.strip() else "\n")
    print("%d words, %d irregular forms, %.1f MB text -> %.1f MB" % (
        len(words), len(syn), len(dict_data) / 1e6, os.path.getsize(out + ".dict.dz") / 1e6))


if __name__ == "__main__":
    main()
