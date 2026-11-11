#!/usr/bin/env python3
"""Check actual DEX class definitions in unminified debug/demo APK outputs."""
import json
import struct
import sys
import zipfile
from pathlib import Path


def definitions(data):
    if not data.startswith(b'dex\n'):
        raise ValueError('Not a DEX file')
    _, strings_offset, _, types_offset = struct.unpack_from('<4I', data, 56)
    count, offset = struct.unpack_from('<2I', data, 96)
    for i in range(count):
        type_id = struct.unpack_from('<I', data, offset + i * 32)[0]
        string_id = struct.unpack_from('<I', data, types_offset + type_id * 4)[0]
        position = struct.unpack_from('<I', data, strings_offset + string_id * 4)[0]
        while data[position] & 128:
            position += 1
        position += 1
        yield data[position:data.index(0, position)].decode('utf-8', errors='replace')


def verify(apk):
    required = {
        'Lcom/osfans/trime/ai/AiRequest;',
        'Lcom/osfans/trime/ai/PromptPackage;',
        'Lcom/osfans/trime/ai/ChatCompletionsClient;',
        'Lcom/osfans/trime/ai/AiFailure;',
        'Lokhttp3/OkHttpClient;',
    }
    with zipfile.ZipFile(apk) as archive:
        found = set()
        for entry in archive.namelist():
            if entry.endswith('.dex'):
                found.update(definitions(archive.read(entry)))
        missing = required - found
        if missing:
            raise RuntimeError(f'{apk.name}: missing DEX definitions: {sorted(missing)}')
        if 'default-prompts.json' not in archive.namelist():
            raise RuntimeError(f'{apk.name}: shared prompts missing')
    print(f'{apk.name}: AI core, transport and prompt resources verified')


if __name__ == '__main__':
    directory = Path(sys.argv[1])
    metadata = json.loads((directory / 'output-metadata.json').read_text(encoding='utf-8'))
    if not metadata['elements']:
        raise RuntimeError('No APK outputs')
    for element in metadata['elements']:
        verify(directory / element['outputFile'])
