"""Pure-Python parser for Android binary XML (AXML) — no Android SDK needed.

Reads AndroidManifest.xml straight out of an APK (it is stored as binary AXML,
not text XML) and returns an xml.etree.ElementTree Element. This makes the
tester self-contained: it can inspect any APK on any machine with Python 3.
A aapt2-based path exists in apk_info.py as a cross-check when available.
"""
import struct
import xml.etree.ElementTree as ET

RES_XML_TYPE = 0x0003
STRING_POOL_TYPE = 0x0001
RES_MAP_TYPE = 0x0180
START_NS = 0x0100
END_NS = 0x0101
START_ELEMENT = 0x0102
END_ELEMENT = 0x0103

ANDROID_URI = "http://schemas.android.com/apk/res/android"
KNOWN_NS_PREFIX = {ANDROID_URI: "android",
                   "http://schemas.android.com/apk/res-auto": "app",
                   "http://schemas.android.com/tools": "tools"}


def _u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def _u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


def _var_len_u16(buf, off):
    """UTF-16 string length: high bit means a second word extends the value."""
    v = _u16(buf, off)
    if v & 0x8000:
        return ((v & 0x7FFF) << 16) | _u16(buf, off + 2), 4
    return v, 2


def _var_len_u8(buf, off):
    v = buf[off]
    if v & 0x80:
        return ((v & 0x7F) << 8) | buf[off + 1], 2
    return v, 1


def parse_string_pool(buf, chunk_off):
    str_count = _u32(buf, chunk_off + 8)
    flags = _u32(buf, chunk_off + 16)
    strings_start = _u32(buf, chunk_off + 20)
    utf8 = bool(flags & 0x100)
    offs = struct.unpack_from("<%dI" % str_count, buf, chunk_off + 28)
    base = chunk_off + strings_start
    out = []
    for o in offs:
        p = base + o
        try:
            if utf8:
                _, n1 = _var_len_u8(buf, p)
                blen, n2 = _var_len_u8(buf, p + n1)
                raw = buf[p + n1 + n2: p + n1 + n2 + blen]
                out.append(raw.decode("utf-8", "replace"))
            else:
                clen, n = _var_len_u16(buf, p)
                raw = buf[p + n: p + n + clen * 2]
                out.append(raw.decode("utf-16-le", "replace"))
        except Exception:
            out.append("")
    return out


def _attr_value(strings, raw, dtype, data):
    if raw != 0xFFFFFFFF:
        return strings[raw] if raw < len(strings) else ""
    if dtype == 0x03:                                   # STRING
        return strings[data] if data < len(strings) else ""
    if dtype == 0x10:                                   # INT_DEC
        return str(struct.unpack("<i", struct.pack("<I", data))[0])
    if dtype == 0x11:                                   # INT_HEX
        return "0x%x" % data
    if dtype == 0x12:                                   # BOOL
        return "true" if data else "false"
    if dtype == 0x04:                                   # FLOAT
        return str(struct.unpack("<f", struct.pack("<I", data))[0])
    if dtype == 0x01:                                   # REFERENCE
        return "@0x%08x" % data
    return "0x%08x" % data


def parse(buf):
    """Parse AXML bytes -> (Element root, dict of chunk metadata)."""
    if len(buf) < 8:
        raise ValueError("not an AXML document: buffer too short")
    rtype, rhdr, rsize = struct.unpack_from("<HHI", buf, 0)
    if rtype != RES_XML_TYPE:
        raise ValueError("not an AXML document: type=0x%04x" % rtype)
    strings, ns_prefix = [], {}
    root = None
    stack = []
    pos = rhdr
    meta = {"res_ids": [], "strings": strings}
    while pos + 8 <= min(rsize, len(buf)):
        ctype, chdr, csize = struct.unpack_from("<HHI", buf, pos)
        if csize <= 0:
            break
        if ctype == STRING_POOL_TYPE:
            strings = parse_string_pool(buf, pos)
            meta["strings"] = strings
        elif ctype == RES_MAP_TYPE:
            n = max(0, (csize - chdr) // 4)
            meta["res_ids"] = list(struct.unpack_from("<%dI" % n, buf, pos + chdr))
        elif ctype == START_NS:
            prefix, uri = _u32(buf, pos + 16), _u32(buf, pos + 20)
            pfx = strings[prefix] if prefix < len(strings) else ""
            ur = strings[uri] if uri < len(strings) else ""
            ns_prefix[ur] = pfx or (KNOWN_NS_PREFIX.get(ur, "ns"))
        elif ctype == START_ELEMENT:
            name_idx = _u32(buf, pos + 20)
            attr_start = _u16(buf, pos + 24)   # relative to attrExt (pos+16)
            attr_count = _u16(buf, pos + 28)
            tag = strings[name_idx] if name_idx < len(strings) else "?"
            elem = ET.Element(tag)
            base = pos + 16 + attr_start
            for i in range(attr_count):
                a = base + i * 20
                ns_i, name_i, raw_i = _u32(buf, a), _u32(buf, a + 4), _u32(buf, a + 8)
                dtype = buf[a + 15]
                data = _u32(buf, a + 16)
                key = strings[name_i] if name_i < len(strings) else "?"
                if ns_i != 0xFFFFFFFF and ns_i < len(strings):
                    uri = strings[ns_i]
                    pfx = ns_prefix.get(uri) or KNOWN_NS_PREFIX.get(uri)
                    if pfx is None and uri.startswith(ANDROID_URI[:20]):
                        pfx = "android"
                    if pfx:
                        key = "%s:%s" % (pfx, key)
                elem.set(key, _attr_value(strings, raw_i, dtype, data))
            if stack:
                stack[-1].append(elem)
            elif root is None:
                root = elem
            stack.append(elem)
        elif ctype == END_ELEMENT:
            if stack:
                stack.pop()
        pos += csize
    if root is None:
        raise ValueError("AXML contained no root element")
    meta["ns_prefix"] = ns_prefix
    return root, meta


def parse_apk_manifest(apk_path):
    """Open an APK file and parse its AndroidManifest.xml."""
    import zipfile
    with zipfile.ZipFile(apk_path) as z:
        data = z.read("AndroidManifest.xml")
    return parse(data)


def write_axml(elem, extra_strings=()):
    """Minimal AXML writer (test helper): tags/attrs as UTF-16 string pool.

    Emits every attribute value as a STRING-typed value, which round-trips
    through parse(). Good enough for unit tests of the parser.
    """
    # 1. collect strings
    pool, index = [], {}

    def intern(s):
        if s not in index:
            index[s] = len(pool)
            pool.append(s)
        return index[s]

    tags = [elem]
    for e in tags:
        intern(e.tag)
        for k, v in e.attrib.items():
            intern(k)
            intern(v)
        tags.extend(e)
    for s in extra_strings:
        intern(s)

    # 2. string pool chunk (UTF-16)
    body = b""
    offsets = []
    for s in pool:
        offsets.append(len(body))
        enc = s.encode("utf-16-le")
        body += struct.pack("<H", len(s)) + enc + b"\x00\x00"
    while len(body) % 4:
        body += b"\x00"
    strings_start = 28 + 4 * len(pool)
    pool_size = strings_start + len(body)
    pool_chunk = struct.pack("<HHIIIIII", STRING_POOL_TYPE, 28, pool_size,
                             len(pool), 0, 0, strings_start, 0) \
        + struct.pack("<%dI" % len(pool), *offsets) + body

    # 3. element chunks
    elems = b""

    def start(tag_idx, attrs):
        # node header(8, headerSize=16) + line(4) + comment(4) + attrExt(20)
        hdr = struct.pack("<HHI", START_ELEMENT, 16, 36 + 20 * len(attrs))
        hdr += struct.pack("<II", 1, 0)          # lineNumber, comment
        hdr += struct.pack("<II", 0xFFFFFFFF, tag_idx)   # ns=-1, name
        hdr += struct.pack("<HHHHHH", 20, 20, len(attrs), 0, 0, 0)
        for k, v in attrs.items():
            hdr += struct.pack("<III", 0xFFFFFFFF, index[k], index[v])
            hdr += struct.pack("<HBBI", 8, 0, 0x03, index[v])   # STRING value
        return hdr

    def end(tag_idx):
        return struct.pack("<HHI", END_ELEMENT, 16, 24) \
            + struct.pack("<II", 1, 0) + struct.pack("<II", 0xFFFFFFFF, tag_idx)

    def walk(e):
        nonlocal elems
        elems += start(index[e.tag], e.attrib)
        for child in e:
            walk(child)
        elems += end(index[e.tag])

    walk(elem)
    body2 = pool_chunk + elems
    return struct.pack("<HHI", RES_XML_TYPE, 8, 8 + len(body2)) + body2
