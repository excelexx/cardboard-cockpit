"""Convert licensed modular GLBs to deduplicated flight-distance glTF assets."""
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.downloads/kominka/KominkaModularHomeLite/addons/kominka_modular_home'
DEST = ROOT / 'simulator/assets/kominka'
DEST.mkdir(parents=True, exist_ok=True)
(DEST / 'textures').mkdir(exist_ok=True)
for source in SOURCE.glob('models/**/*.glb'):
    raw = source.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    image_views = set()
    for image in doc.get('images', []):
        index = image.pop('bufferView')
        image_views.add(index)
        view = doc['bufferViews'][index]
        data = binary[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']]
        filename = hashlib.sha256(data).hexdigest()[:20]+'.png'
        path = DEST / 'textures' / filename
        if not path.exists():
            bitmap = Image.open(io.BytesIO(data))
            bitmap.thumbnail((512, 512), Image.Resampling.LANCZOS)
            bitmap.save(path, optimize=True)
        image.pop('mimeType', None)
        image['uri'] = 'textures/'+filename
    output = bytearray()
    # Retain view indices referenced by accessors; image-only views become empty
    # unused four-byte views. No geometry or vertex attributes are changed.
    for index, view in enumerate(doc['bufferViews']):
        data = b'\0'*4 if index in image_views else binary[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']]
        view['byteOffset'] = len(output)
        view['byteLength'] = len(data)
        output.extend(data)
        output.extend(b'\0' * (-len(output) % 4))
    doc['buffers'] = [{'uri': source.stem+'.bin', 'byteLength': len(output)}]
    (DEST / (source.stem+'.bin')).write_bytes(output)
    (DEST / (source.stem+'.gltf')).write_text(json.dumps(doc))
    subprocess.run(['node', str(ROOT/'.tools/mesh-tools/node_modules/gltfpack/cli.js'),
                    '-i', str(DEST/(source.stem+'.gltf')),
                    '-o', str(DEST/(source.stem+'.gltf')),
                    '-si', '0.35', '-sp', '-se', '0.025', '-noq', '-tr'], check=True)
shutil.copy2(SOURCE / 'LICENSE', DEST / 'LICENSE')
shutil.copy2(SOURCE / 'demo/Exterior_layout.json', DEST / 'layout.json')
print('Prepared', len(list(DEST.glob('*.gltf'))), 'modules;', len(list((DEST/'textures').glob('*.png'))), 'shared textures')
