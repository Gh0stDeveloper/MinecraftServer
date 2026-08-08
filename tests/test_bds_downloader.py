#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import io
import tempfile
import urllib.error
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = ROOT / "scripts" / "bds-downloader.py"
SPEC = importlib.util.spec_from_file_location("bds_downloader", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

URL = "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.26.43.1.zip"


class FakeResponse(io.BytesIO):
    def __init__(self, payload: bytes, url: str = URL):
        super().__init__(payload)
        self._url = url

    def geturl(self) -> str:
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def make_bds_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("bedrock_server", b"fake-bds-binary")
        archive.writestr("server.properties", b"server-name=test\n")
    return buffer.getvalue()


def main() -> None:
    payload = make_bds_zip()
    expected_sha1 = hashlib.sha1(payload).hexdigest()
    calls = [urllib.error.URLError("simulated transport reset"), FakeResponse(payload)]

    def fake_urlopen(*_args, **_kwargs):
        item = calls.pop(0)
        if isinstance(item, Exception):
            raise item
        return item

    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "bedrock.zip"
        with mock.patch.object(MODULE.urllib.request, "urlopen", side_effect=fake_urlopen):
            result = MODULE.download(
                URL,
                output,
                expected_size=len(payload),
                expected_sha1=expected_sha1,
                attempts=2,
                sleep_seconds=0,
            )
        assert result == output
        assert output.read_bytes() == payload
        assert not Path(f"{output}.part").exists()
        assert calls == []

        bad = Path(tmp) / "bad.zip"
        bad.write_bytes(payload)
        try:
            MODULE.validate_archive(bad, len(payload) + 1, expected_sha1)
        except ValueError as exc:
            assert "Tamaño BDS incorrecto" in str(exc)
        else:
            raise AssertionError("A size mismatch was accepted")

    print("BDS downloader retry/integrity tests passed.")


if __name__ == "__main__":
    main()
