import shutil
import struct
from pathlib import Path
import os

prefix = os.environ.get("PREFIX", "/data/data/com.termux/files/usr")
bin_path = Path(f"{prefix}/var/lib/proot-distro/containers/debian/rootfs/opt/antigravity/resources/bin/language_server")
bak_path = Path(str(bin_path) + ".bak")
flag_path = Path(str(bin_path) + ".patched")

if not bin_path.exists():
    print("Warning: language_server not found. Skipping binary patch.")
    exit(0)

# Check if already patched by looking at our mmap signature
try:
    data = bytearray(bin_path.read_bytes())
    if data.count(struct.pack("<I", 0xD2C00409)) > 0 and data.count(struct.pack("<I", 0xD2C20009)) == 0:
        print("   \033[1;32m✓\033[0m  VA39 binary patch already applied.")
        flag_path.touch()
        exit(0)
except Exception as e:
    print(f"Error reading {bin_path}: {e}")
    exit(1)

print("   \033[1;36mℹ\033[0m  \033[2mUnpatched binary detected. Applying VA39 patch...\033[0m")

# Create backup of the unpatched binary if it doesn't exist
if not bak_path.exists():
    shutil.copyfile(bin_path, bak_path)
elif os.path.getmtime(bin_path) > os.path.getmtime(bak_path):
    shutil.copyfile(bin_path, bak_path)

data = bytearray(bak_path.read_bytes())

def get(off): return struct.unpack_from("<I", data, off)[0]
def put(off, word): struct.pack_into("<I", data, off, word)

def find_section(name_target):
    if data[:4] != b"\x7fELF": return None, None
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]
    shstr_base = e_shoff + e_shstrndx * e_shentsize
    shstr_off = struct.unpack_from("<Q", data, shstr_base + 24)[0]
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        sh_name = struct.unpack_from("<I", data, base)[0]
        sh_offset = struct.unpack_from("<Q", data, base + 24)[0]
        sh_size = struct.unpack_from("<Q", data, base + 32)[0]
        nend = data.index(b"\x00", shstr_off + sh_name)
        section = data[shstr_off + sh_name : nend].decode("utf-8", errors="replace")
        if section == name_target:
            return sh_offset, sh_offset + sh_size
    return None, None

lo, hi = 0, len(data)
sec_lo, sec_hi = find_section("google_malloc")
if sec_lo is not None: lo, hi = sec_lo, sec_hi
else:
    sec_lo, sec_hi = find_section(".text")
    if sec_lo is not None: lo, hi = sec_lo, sec_hi

word_rewrites = {
    0xD2C20009: 0xD2C00409, 0xD2C2000A: 0xD2C0040A,
    0xF2C20008: 0xF2DFF408, 0xF2C20009: 0xF2DFF409,
    0xD2C10009: 0xD2C00209, 0xD2C1000A: 0xD2C0020A,
    0xF2C38008: 0xF2DFF708, 0xF2C38009: 0xF2DFF709,
    0x92560A6C: 0x925D0A6C, 0x92560A6A: 0x925D0A6A,
    0xD2C3000D: 0xD2C0060D, 0xD2C3000C: 0xD2C0060C,
    0xD2C08008: 0xD2C00108,
}

ubfx_count = lsl_count = mask_count = mmap_count = tags_count = 0
for off in range(lo, hi, 4):
    w = get(off)
    if (w & 0x7F800000) == 0x53000000:
        immr = (w >> 16) & 0x3F
        imms = (w >> 10) & 0x3F
        if immr == 42 and imms == 44:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10))
            ubfx_count += 1
        elif immr == 22 and imms == 21:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10))
            lsl_count += 1
    elif w == 0xF2E00029:
        put(off, 0xD3596129)
        mmap_count += 1
    elif w == 0x92D3800A and off + 4 < hi and get(off + 4) == 0xF2E0000A:
        put(off, 0x9280000A)
        put(off + 4, 0xD35DFD4A)
        mask_count += 1
    elif w in word_rewrites:
        put(off, word_rewrites[w])
        tags_count += 1

bin_path.write_bytes(data)
bin_path.chmod(0o755)
flag_path.touch()

print(f"   \033[1;36mℹ\033[0m  \033[2mPatches applied: UBFX={ubfx_count}, LSL={lsl_count}, MASK={mask_count}, MMAP={mmap_count}, TAGS={tags_count}\033[0m")
print("   \033[1;32m✓\033[0m  Native VA39 Binary Patch applied successfully.")
