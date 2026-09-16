"""Polar 0.1.92 (20260913071337), arm64. Refuse every other binary."""
import hashlib
import struct

SOURCE_SHA256 = 'f7e1bcbc432a404cfbe0498f85eb0672375793dda3acfa2632acba9aba823fed'

# Addresses and preimages from the actual arm64 Polar 0.1.92 / 20260913071337.
# Each change replaces one instruction. No Chromium code or fullscreen state changes.
PATCHES = [
    (0x100098D38, 0x12000342, 0x52800022, 'Hide native tab strip'),
    (0x100098E10, 0x1E691DA0, 0x1E631000, 'Reserve six points at the top instead of the tab row'),
    (0x100098E18, 0xAA1503E0, 0x52800020, 'Hide tab-strip profile avatar'),
    (0x100098E28, 0xAA1503E0, 0x52800020, 'Hide tab-strip leading accessory'),
    (0x10009904C, 0x120002C0, 0x52800020, 'Use existing zero-height toolbar measurement path'),
    (0x100099088, 0x1E601C2C, 0x6F00E40C, 'Remove bookmark-bar reserved height'),
    (0x100099550, 0x0A360102, 0x52800022, 'Hide toolbar hosting view, including URL and extensions'),
    (0x100099600, 0x12000102, 0x52800022, 'Hide bookmark-bar hosting view'),
    (0x100099814, 0x0A360102, 0x52800022, 'Hide obsolete tab-strip border overlay'),
    (0x1002AB0A4, 0xAA0003F4, 0x52800034, 'Hide traffic lights to match the supplied Arc reference'),
    (0x10009CB80, 0x120002A2, 0x52800022, 'Hide the collapsed sidebar button'),
    (0x10009A69C, 0x52800182, 0x528001E2, 'Round the top page corners using the existing bottom radius'),
    (0x10009A66C, 0x52800082, 0x528001E2, 'Round page corners when the command panel is present'),
]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def file_offset(data, address):
    """Translate a VM address using Mach-O segment mappings, never a guessed base."""
    magic, cpu, _, _, commands, command_bytes, _, _ = struct.unpack_from('<8I', data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError('Expected a thin arm64 Mach-O executable')
    cursor = 32
    limit = 32 + command_bytes
    for _ in range(commands):
        command, size = struct.unpack_from('<II', data, cursor)
        if size < 8 or cursor + size > limit:
            raise ValueError('Invalid Mach-O load command')
        if command == 0x19:
            vmaddr, _, offset, file_size = struct.unpack_from('<4Q', data, cursor + 24)
            if vmaddr <= address and address + 4 <= vmaddr + file_size:
                return offset + address - vmaddr
        cursor += size
    raise ValueError('Patch address is outside file-backed segments')


def patched_bytes(original):
    if sha256(original) != SOURCE_SHA256:
        raise ValueError('Unsupported Polar binary. Refusing to patch a different build.')
    modified = bytearray(original)
    changes = []
    for address, before, after, purpose in PATCHES:
        offset = file_offset(original, address)
        actual = struct.unpack_from('<I', original, offset)[0]
        if actual != before:
            raise ValueError('Unexpected instruction at ' + hex(address))
        struct.pack_into('<I', modified, offset, after)
        changes.append(dict(address=hex(address), offset=offset, before=hex(before),
                            after=hex(after), purpose=purpose))
    return bytes(modified), changes
