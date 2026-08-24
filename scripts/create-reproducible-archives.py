#!/usr/bin/env python3
"""Create byte-for-byte reproducible UnpackFlow release archives."""

from __future__ import annotations

import gzip
import os
import pathlib
import stat
import sys
import tarfile
import zipfile


def entries(root: pathlib.Path):
    yield from sorted(root.rglob("*"), key=lambda p: p.relative_to(root).as_posix())


def normalized_mode(path: pathlib.Path) -> int:
    if path.is_dir():
        return 0o755
    return 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644


def tar_gz(source: pathlib.Path, output: pathlib.Path, epoch: int, prefix: str = "") -> None:
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch, compresslevel=9) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as archive:
                if prefix:
                    root_info = tarfile.TarInfo(prefix.rstrip('/') + '/')
                    root_info.mtime = epoch; root_info.uid = root_info.gid = 0
                    root_info.uname = root_info.gname = "root"; root_info.mode = 0o755; root_info.type = tarfile.DIRTYPE
                    archive.addfile(root_info)
                for path in entries(source):
                    name = prefix + path.relative_to(source).as_posix()
                    info = tarfile.TarInfo(name + ("/" if path.is_dir() else ""))
                    info.mtime = epoch
                    info.uid = info.gid = 0
                    info.uname = info.gname = "root"
                    info.mode = normalized_mode(path)
                    info.pax_headers = {}
                    if path.is_dir():
                        info.type = tarfile.DIRTYPE
                        archive.addfile(info)
                    else:
                        info.size = path.stat().st_size
                        with path.open("rb") as stream:
                            archive.addfile(info, stream)


def zip_file(source: pathlib.Path, output: pathlib.Path, epoch: int) -> None:
    # ZIP cannot represent dates before 1980 and stores two-second resolution.
    import datetime

    dt = datetime.datetime.fromtimestamp(max(epoch, 315532800), datetime.timezone.utc)
    stamp = (dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second // 2 * 2)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in entries(source):
            name = path.relative_to(source).as_posix() + ("/" if path.is_dir() else "")
            info = zipfile.ZipInfo(name, stamp)
            info.create_system = 3
            info.external_attr = (normalized_mode(path) | (stat.S_IFDIR if path.is_dir() else stat.S_IFREG)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.extra = b""
            info.comment = b""
            archive.writestr(info, b"" if path.is_dir() else path.read_bytes())


def main() -> None:
    if len(sys.argv) == 6 and sys.argv[1] == "source":
        epoch, source, output, prefix = int(sys.argv[2]), pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]), sys.argv[5].rstrip('/') + '/'
        output.parent.mkdir(parents=True, exist_ok=True)
        tar_gz(source, output, epoch, prefix)
        return
    if len(sys.argv) != 6:
        raise SystemExit("usage: create-reproducible-archives.py EPOCH LINUX MACOS WINDOWS OUTPUT | source EPOCH SOURCE OUTPUT PREFIX")
    epoch = int(sys.argv[1])
    linux, macos, windows, output = map(pathlib.Path, sys.argv[2:])
    output.mkdir(parents=True, exist_ok=True)
    version = os.environ["UNPACK_FLOW_VERSION"]
    tar_gz(linux, output / f"unpack-flow-{version}-linux.tar.gz", epoch)
    tar_gz(macos, output / f"unpack-flow-{version}-macos.tar.gz", epoch)
    zip_file(windows, output / f"unpack-flow-{version}-windows.zip", epoch)


if __name__ == "__main__":
    main()
