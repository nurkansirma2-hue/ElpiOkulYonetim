#!/usr/bin/env python3
"""Reject Android APKs containing ELF shared libraries incompatible with 16 KiB pages."""
import argparse
import struct
import sys
import zipfile

PAGE = 16 * 1024
PT_LOAD = 1


def check_elf(name, content):
    problems = []
    if content[:4] != b"\x7fELF":
        return [f"{name}: not an ELF file"]
    elf_class, encoding = content[4], content[5]
    if encoding not in (1, 2) or elf_class not in (1, 2):
        return [f"{name}: unsupported ELF format"]
    order = "<" if encoding == 1 else ">"
    if elf_class == 2:
        header_fmt, ph_fmt = order + "Q", order + "IIQQQQQQ"
        header_offset, count_offset, size_offset = 32, 56, 54
        offset_idx, vaddr_idx, align_idx = 2, 3, 7
    else:
        header_fmt, ph_fmt = order + "I", order + "IIIIIIII"
        header_offset, count_offset, size_offset = 28, 44, 42
        offset_idx, vaddr_idx, align_idx = 1, 2, 7
    try:
        phoff = struct.unpack_from(header_fmt, content, header_offset)[0]
        phnum = struct.unpack_from(order + "H", content, count_offset)[0]
        phentsize = struct.unpack_from(order + "H", content, size_offset)[0]
        expected = struct.calcsize(ph_fmt)
        if phentsize < expected or phnum == 0:
            return [f"{name}: missing/invalid ELF program headers"]
        loads = 0
        for index in range(phnum):
            entry = struct.unpack_from(ph_fmt, content, phoff + index * phentsize)
            if entry[0] != PT_LOAD:
                continue
            loads += 1
            offset, vaddr, alignment = (entry[offset_idx], entry[vaddr_idx], entry[align_idx])
            if alignment < PAGE or offset % PAGE != vaddr % PAGE:
                problems.append(
                    f"{name}: PT_LOAD #{index} offset={offset:#x} "
                    f"vaddr={vaddr:#x} p_align={alignment:#x}; 16 KiB required"
                )
        if loads == 0:
            problems.append(f"{name}: no PT_LOAD program headers")
    except (struct.error, IndexError) as exc:
        problems.append(f"{name}: invalid ELF headers: {exc}")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", help="APK path")
    args = parser.parse_args()
    problems = []
    checked = 0
    with zipfile.ZipFile(args.apk) as apk:
        for name in apk.namelist():
            if not (name.startswith("lib/") and name.endswith(".so")):
                continue
            checked += 1
            problems.extend(check_elf(name, apk.read(name)))
    if not checked:
        problems.append("No native .so files found in APK (unexpected for Flutter)")
    if problems:
        print("FAIL: 16 KiB ELF load segment validation:")
        for error in problems:
            print(" -", error)
        return 1
    print(f"PASS: {checked} native ELF libraries meet 16 KiB load segment alignment")
    return 0


if __name__ == "__main__":
    sys.exit(main())
