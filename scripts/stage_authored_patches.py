#!/usr/bin/env python3
"""Stage exact authored Git blobs; never parse or serialize their YAML payloads."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

PATCH = re.compile(r"ob-issues/([1-9][0-9]*)/([a-z][a-z0-9-]*)/([0-9]{3})-(ADD|SUP|REP|LIR|MOD|DEL|SEED)\.yaml\Z")
META = re.compile(r"ob-issues/([1-9][0-9]*)/meta\.yaml\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def commit(root, value):
    if not SHA.fullmatch(value):
        raise ValueError("refs must be explicit lowercase 40-character commit SHAs")
    resolved = git(root, "rev-parse", "--verify", value + "^{commit}").decode().strip()
    if resolved != value:
        raise ValueError(f"not an exact commit: {value}")
    return resolved


def safe_path(root, relative):
    path = PurePosixPath(relative)
    if path.is_absolute() or any(part in (".", "..") for part in relative.split("/")):
        raise ValueError(f"unsafe path: {relative}")
    target = root
    if root.is_symlink():
        raise ValueError(f"symlink root: {root}")
    for part in path.parts:
        target = target / part
        if target.is_symlink():
            raise ValueError(f"symlink path: {target}")
    return target


def permitted_nonpatch(path):
    # Legacy source and inert repository maintenance files may accompany a PR.
    # Nothing from these directories is executed by this workflow.
    return (path.startswith("issues/") or path.startswith("docs/")
            or re.fullmatch(r"\.github/workflows/[a-zA-Z0-9_.-]+\.ya?ml", path)
            or re.fullmatch(r"\.github/scripts/[a-zA-Z0-9][a-zA-Z0-9_.-]*\.(?:sh|py)", path)
            or path in {"README.md", "README.adoc", "LICENSE", "LICENSE.md", ".gitignore"})


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stage(data_root, service_root, base, head, manifest_path):
    base = commit(data_root, base)
    head = commit(data_root, head)
    if git(data_root, "rev-parse", "HEAD").decode().strip() != head:
        raise ValueError("data checkout HEAD does not match data_ref")

    tree = {}
    for entry in git(data_root, "ls-tree", "-rz", head).split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        path = raw_path.decode("utf-8")
        if mode not in ("100644", "100755") or kind != "blob":
            raise ValueError(f"symlink/submodule/nonregular data entry: {path}")
        tree[path] = (mode, oid)

    tokens = git(data_root, "diff", "--name-status", "--no-renames", "-z", base, head, "--").split(b"\0")
    changes = list(zip(tokens[0:-1:2], tokens[1:-1:2]))
    source_changed = False
    changed_paths = []
    for raw_status, raw_path in changes:
        status, path = raw_status.decode(), raw_path.decode("utf-8")
        safe_path(data_root, path)
        match = PATCH.fullmatch(path) or META.fullmatch(path)
        if match:
            if status != "A":
                raise ValueError(f"authored history cannot be modified/deleted: {status} {path}")
            changed_paths.append(path)
        else:
            if path.startswith("ob-issues/") or not permitted_nonpatch(path):
                raise ValueError(f"unsupported or generated-state write: {path}")
            source_changed |= path.startswith("issues/")

    # Replay needs the cumulative head, including patches authored in earlier
    # data PRs that are not yet present in the legacy service corpus.
    pending = []
    for path, (mode, oid) in sorted(tree.items()):
        match = PATCH.fullmatch(path) or META.fullmatch(path)
        if not match:
            if path.startswith("ob-issues/"):
                raise ValueError(f"unsupported authored corpus entry: {path}")
            continue
        source_path = safe_path(data_root, path)
        if mode != "100644":
            raise ValueError(f"patch must be a nonexecutable regular file: {path}")
        payload = git(data_root, "cat-file", "blob", oid)
        if not source_path.is_file() or source_path.read_bytes() != payload:
            raise ValueError(f"data checkout differs from head blob: {path}")
        target = safe_path(service_root, path)
        if target.exists() and (not target.is_file() or target.read_bytes() != payload):
            raise ValueError(f"historical corpus collision with different bytes: {path}")
        pending.append((path, payload, target))

    incoming_paths = {path for path, _, _ in pending}
    for path, _, _ in pending:
        match = PATCH.fullmatch(path)
        if match:
            meta_path = f"ob-issues/{match[1]}/meta.yaml"
            meta = safe_path(service_root, meta_path)
            if not meta.is_file() and meta_path not in incoming_paths:
                raise ValueError(f"issue metadata prerequisite missing: {meta_path}; add it in the same PR")

    manifest = {"base_ref": base, "data_ref": head,
                "source_changed": source_changed, "changed_paths": changed_paths, "patches": []}
    for path, payload, target in pending:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        manifest["patches"].append({"path": path, "sha256": digest(payload)})
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def check(data_root, service_root, manifest_path):
    manifest = json.loads(manifest_path.read_text())
    if git(data_root, "rev-parse", "HEAD").decode().strip() != manifest["data_ref"]:
        raise ValueError("data checkout HEAD changed during validation")
    for entry in manifest["patches"]:
        path = entry["path"]
        if not (PATCH.fullmatch(path) or META.fullmatch(path)):
            raise ValueError(f"invalid manifest patch path: {path}")
        blob = git(data_root, "show", f'{manifest["data_ref"]}:{path}')
        if digest(blob) != entry["sha256"]:
            raise ValueError(f"manifest differs from exact head blob: {path}")
        for root in (data_root, service_root):
            target = safe_path(root, path)
            if not target.is_file() or digest(target.read_bytes()) != entry["sha256"]:
                raise ValueError(f"incoming bytes changed during validation: {target}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stage", "check"))
    parser.add_argument("--data-root", type=Path, required=True)
    parser.add_argument("--service-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--base-ref")
    parser.add_argument("--data-ref")
    args = parser.parse_args()
    try:
        if args.command == "stage":
            if not args.base_ref or not args.data_ref:
                parser.error("stage requires --base-ref and --data-ref")
            manifest = stage(args.data_root, args.service_root, args.base_ref, args.data_ref, args.manifest)
        else:
            manifest = check(args.data_root, args.service_root, args.manifest)
        print(f'{args.command}: {len(manifest["patches"])} authored patches; bytes verified')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"authored patch gate: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
