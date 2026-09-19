"""Select LODs from Helsinki's CC BY 4.0 city mesh without fetching entire archives."""
import io
import urllib.request
import zipfile
import argparse
import concurrent.futures
import struct
import zlib
from pathlib import Path

BASE = "https://3d.hel.ninja/data/mesh/Helsinki3D-MESH_2017_OBJ_2km-250m_ZIP/"

class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60) as r:
            self.length = int(r.headers["Content-Length"])
        self.pos = 0
        self.cache_start = max(0, self.length - 4 * 1024 * 1024)
        self.cache = self.fetch(self.cache_start, self.length - 1)

    def fetch(self, begin, end):
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={begin}-{end}"})
        with urllib.request.urlopen(req, timeout=90) as r:
            if r.status != 206:
                raise RuntimeError("Server ignored byte range; refusing full archive download")
            return r.read()

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos if whence == 1 else self.length) + offset
        return self.pos
    def read(self, size=-1):
        size = min(self.length-self.pos, size if size >= 0 else self.length)
        if size <= 0: return b""
        if self.pos >= self.cache_start:
            data = self.cache[self.pos-self.cache_start:self.pos-self.cache_start+size]
        else:
            data = self.fetch(self.pos, self.pos+size-1)
        self.pos += len(data)
        return data

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--tile", default="672496")
    parser.add_argument("--match", default="")
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    if not args.tile.isdigit(): raise ValueError("Numeric tile ID required")
    url = BASE + f"Helsinki3D_2017_OBJ_{args.tile}x2.zip"
    destination = Path(__file__).resolve().parents[1] / ".downloads/helsinki" / args.tile
    with zipfile.ZipFile(RemoteZip(url)) as archive:
        selected = [i for i in archive.infolist() if not i.is_dir() and (args.match in i.filename or i.filename == "metadata.xml")]
        print("SELECTED",len(selected),"files",sum(i.compress_size for i in selected),"compressed bytes",flush=True)
        for item in selected[:20]: print(item.filename,item.file_size,item.compress_size,flush=True)
        def transfer(item):
            if args.download:
                relative = Path(item.filename)
                if relative.is_absolute() or ".." in relative.parts: raise ValueError("Unsafe archive path")
                path = destination / relative
                if path.exists() and path.stat().st_size == item.file_size: return
                path.parent.mkdir(parents=True, exist_ok=True)
                # One bounded request per entry; never share a seek pointer across workers.
                block=archive.fp.fetch(item.header_offset,min(archive.fp.length-1,item.header_offset+30+len(item.filename.encode())+item.compress_size+1024))
                if block[:4] != b"PK\x03\x04": raise ValueError("Invalid ZIP header")
                name_size,extra_size=struct.unpack_from("<HH",block,26)
                offset=30+name_size+extra_size
                compressed=block[offset:offset+item.compress_size]
                data=zlib.decompress(compressed,-15) if item.compress_type==zipfile.ZIP_DEFLATED else compressed
                if len(data)!=item.file_size or zlib.crc32(data)!=item.CRC: raise ValueError("ZIP integrity mismatch")
                path.write_bytes(data)
        if args.download:
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(transfer,selected))
            print("DOWNLOADED",destination,flush=True)
