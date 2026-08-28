#!/usr/bin/env python3
"""Fail CI when an unsigned Note Eryk IPA cannot be resigned/installed safely."""

from __future__ import annotations

import io
import plistlib
import re
import sys
import zipfile
from pathlib import Path


APP_PLIST = "Payload/Runner.app/Info.plist"
EXTENSION_ROOT = "Payload/Runner.app/PlugIns/ShareExtension.appex"
EXTENSION_PLIST = f"{EXTENSION_ROOT}/Info.plist"
APP_SIGNATURE = "Payload/Runner.app/_CodeSignature/CodeResources"
EXTENSION_SIGNATURE = f"{EXTENSION_ROOT}/_CodeSignature/CodeResources"
BUILD_VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+){0,2}$")
RELEASE_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


class ValidationError(RuntimeError):
    pass


def _required_string(data: dict, key: str, bundle: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{bundle} is missing {key}")
    return value.strip()


def _read_plist(archive: zipfile.ZipFile, path: str) -> dict:
    try:
        return plistlib.loads(archive.read(path))
    except KeyError as error:
        raise ValidationError(f"IPA is missing {path}") from error
    except Exception as error:
        raise ValidationError(f"Cannot parse {path}: {error}") from error


def validate_archive(archive: zipfile.ZipFile) -> dict[str, str]:
    names = set(archive.namelist())
    app = _read_plist(archive, APP_PLIST)
    extension = _read_plist(archive, EXTENSION_PLIST)

    app_id = _required_string(app, "CFBundleIdentifier", "Runner.app")
    extension_id = _required_string(
        extension, "CFBundleIdentifier", "ShareExtension.appex"
    )
    if not extension_id.startswith(f"{app_id}."):
        raise ValidationError(
            "ShareExtension bundle ID must start with the containing app bundle ID"
        )

    app_version = _required_string(
        app, "CFBundleShortVersionString", "Runner.app"
    )
    extension_version = _required_string(
        extension, "CFBundleShortVersionString", "ShareExtension.appex"
    )
    app_build = _required_string(app, "CFBundleVersion", "Runner.app")
    extension_build = _required_string(
        extension, "CFBundleVersion", "ShareExtension.appex"
    )
    if not RELEASE_VERSION.fullmatch(app_version):
        raise ValidationError(f"Invalid app release version: {app_version}")
    if not BUILD_VERSION.fullmatch(app_build):
        raise ValidationError(f"Invalid app build version: {app_build}")
    if extension_version != app_version or extension_build != app_build:
        raise ValidationError("App and ShareExtension versions must match")

    if app.get("CFBundlePackageType") != "APPL":
        raise ValidationError("Runner.app must have CFBundlePackageType APPL")
    if extension.get("CFBundlePackageType") != "XPC!":
        raise ValidationError("ShareExtension.appex must have CFBundlePackageType XPC!")

    extension_point = (
        extension.get("NSExtension", {}).get("NSExtensionPointIdentifier")
    )
    if extension_point != "com.apple.share-services":
        raise ValidationError("ShareExtension has the wrong extension point")

    for data, bundle, root in (
        (app, "Runner.app", "Payload/Runner.app"),
        (extension, "ShareExtension.appex", EXTENSION_ROOT),
    ):
        executable = _required_string(data, "CFBundleExecutable", bundle)
        executable_path = f"{root}/{executable}"
        if executable_path not in names:
            raise ValidationError(f"IPA is missing executable {executable_path}")
        if archive.getinfo(executable_path).file_size == 0:
            raise ValidationError(f"Executable is empty: {executable_path}")
        if data.get("UIDeviceFamily") != [2]:
            raise ValidationError(f"{bundle} is not configured as iPad-only")

    # These are ad-hoc signatures, not device-installable signatures. Their
    # purpose is to carry the requested entitlements into the IPA so a signing
    # tool can provision and replace them with the user's development profile.
    for signature in (APP_SIGNATURE, EXTENSION_SIGNATURE):
        if signature not in names or archive.getinfo(signature).file_size == 0:
            raise ValidationError(f"IPA is missing signing metadata {signature}")

    return {
        "app_id": app_id,
        "extension_id": extension_id,
        "version": app_version,
        "build": app_build,
    }


def validate_ipa(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise ValidationError(f"IPA not found: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            bad_entry = archive.testzip()
            if bad_entry is not None:
                raise ValidationError(f"Corrupt IPA entry: {bad_entry}")
            return validate_archive(archive)
    except zipfile.BadZipFile as error:
        raise ValidationError(f"Invalid IPA zip: {error}") from error


def _plist(
    identifier: str,
    package_type: str,
    executable: str,
    *,
    extension: bool = False,
) -> bytes:
    data = {
        "CFBundleIdentifier": identifier,
        "CFBundlePackageType": package_type,
        "CFBundleExecutable": executable,
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "UIDeviceFamily": [2],
    }
    if extension:
        data["NSExtension"] = {
            "NSExtensionPointIdentifier": "com.apple.share-services"
        }
    return plistlib.dumps(data)


def self_test() -> None:
    payload = io.BytesIO()
    with zipfile.ZipFile(payload, "w") as archive:
        archive.writestr(
            APP_PLIST,
            _plist("com.example.noteeryk", "APPL", "Runner"),
        )
        archive.writestr("Payload/Runner.app/Runner", b"runner")
        archive.writestr(
            EXTENSION_PLIST,
            _plist(
                "com.example.noteeryk.ShareExtension",
                "XPC!",
                "ShareExtension",
                extension=True,
            ),
        )
        archive.writestr(f"{EXTENSION_ROOT}/ShareExtension", b"extension")
        archive.writestr(APP_SIGNATURE, b"app-signature-metadata")
        archive.writestr(EXTENSION_SIGNATURE, b"extension-signature-metadata")
    payload.seek(0)
    with zipfile.ZipFile(payload) as archive:
        validate_archive(archive)
    print("IPA validator self-test passed")


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
            self_test()
            return 0
        if len(sys.argv) != 2:
            print("Usage: validate_ios_ipa.py <ipa-path>", file=sys.stderr)
            return 2
        result = validate_ipa(Path(sys.argv[1]))
        print(
            "IPA valid: "
            f"{result['app_id']} + {result['extension_id']} "
            f"version={result['version']} build={result['build']}"
        )
        return 0
    except ValidationError as error:
        print(f"IPA validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
