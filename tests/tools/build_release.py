"""Build or verify the portable release payload from immutable Git bytes.

The release ZIP is a filtered `git archive` of one commit: repository metadata,
tests, validator and spec files are dropped, and every shipped file must match the
raw blob of that commit byte for byte. Nothing here writes to Windows configuration,
the registry or a user profile; it only reads Git objects and writes the archive and
its report. Run it from the repository root with Python 3:

    python tests/tools/build_release.py build dist/Windows-PC-Toolkit-X.Y.Z.zip <sha> --report build.json
    python tests/tools/build_release.py verify Windows-PC-Toolkit-X.Y.Z.zip <sha> --report verify.json

The report records the commit, file count, size, SHA-256 and any payload file whose
bytes differ from the commit. `build` refuses to overwrite an existing archive.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile

# Every payload path is relative to this top folder inside the archive.
PREFIX = "Windows-PC-Toolkit/"

# Paths that belong to the project, not to the running toolkit. Keep this list the
# single source of truth: a file added here stops shipping, and the byte check still
# covers everything that does ship.
EXCLUDED_TOP = {".github", "tests", "AGENTS.md", "STATE.md", ".gitignore",
                "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md"}
EXCLUDED_PREFIXES = {("docs", "specs")}


def git(*args):
    """Run git and return raw stdout; a missing blob raises instead of being skipped."""
    return subprocess.check_output(["git", *args])


def payload(path):
    """True when a repository path ships to users."""
    parts = PurePosixPath(path).parts
    return (parts[0] not in EXCLUDED_TOP
            and parts[:2] not in EXCLUDED_PREFIXES
            and not parts[-1].lower().startswith("validate_"))


def verify(archive, commit):
    """Compare every archive entry with the raw blob at `commit`; report, never repair."""
    raw, normalized = [], []
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            if entry.is_dir():
                continue
            assert entry.filename.startswith(PREFIX), entry.filename
            path = entry.filename[len(PREFIX):]
            assert not PurePosixPath(path).is_absolute() and ".." not in PurePosixPath(path).parts
            actual = package.read(entry)
            expected = git("cat-file", "blob", f"{commit}:{path}")
            if actual != expected:
                raw.append(path)
            if actual.replace(b"\r\n", b"\n") != expected.replace(b"\r\n", b"\n"):
                normalized.append(path)
        files = sum(not i.is_dir() for i in package.infolist())
    return {"commit": commit, "archive": str(archive), "files": files,
            "size": archive.stat().st_size, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "rawMismatches": raw, "newlineNormalizedMismatches": normalized}


def build(archive, commit):
    """Archive the commit, drop non-payload paths, and fail if any shipped byte differs."""
    source = archive.with_name("source-commit.zip")
    assert not archive.exists() and not source.exists(), "Refuse to overwrite a prior artifact"
    # Git applies checkout EOL filters to `archive`; disable the user's CRLF conversion
    # for this command only so payload bytes stay equal to the committed blobs.
    subprocess.run(["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf", "archive", "--format=zip",
                    "--prefix=" + PREFIX, "--output=" + str(source), commit], check=True)
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for entry in original.infolist():
            if entry.is_dir() or not payload(entry.filename[len(PREFIX):]):
                continue
            package.writestr(entry, original.read(entry), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    report = verify(archive, commit)
    assert not report["rawMismatches"], report["rawMismatches"]
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["build", "verify"])
    parser.add_argument("archive", type=Path)
    parser.add_argument("commit")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.archive, args.commit) if args.mode == "build" else verify(args.archive, args.commit)
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in {"rawMismatches", "newlineNormalizedMismatches"}}))
    print("Raw mismatches:", len(result["rawMismatches"]), "Normalized mismatches:", len(result["newlineNormalizedMismatches"]))
    if result["newlineNormalizedMismatches"]:
        raise SystemExit(1)
