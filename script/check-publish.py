"""Audit source publication without staging, committing, uploading or printing secrets."""
from pathlib import Path
import collections
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    result = subprocess.run(
        ["git", "-c", f"safe.directory={ROOT.as_posix()}", *args],
        cwd=ROOT, capture_output=True, check=True,
    )
    return [x.decode("utf-8") for x in result.stdout.split(b"\0") if x]


def main():
    ignored_tracked = git("ls-files", "-ci", "--exclude-standard", "-z")
    candidates = sorted(set(git("ls-files", "-co", "--exclude-standard", "-z")))
    files = [name for name in candidates if (ROOT / name).is_file()]
    required = [
        ".gitignore", "README.md", "LICENSE", "AUTHORS", "PRIVACY.md",
        "build.gradle.kts", "settings.gradle.kts", "gradlew", "gradlew.bat",
        "gradle/wrapper/gradle-wrapper.jar", "docs/DEVELOPMENT.md", "docs/PUBLISHING.md",
        "android/app/build.gradle.kts", "android/app/src/main/jni/CMakeLists.txt",
        "android/app/src/main/assets/ai/default-prompts.json",
        "shared/ai-core/src/main/resources/default-prompts.json",
        "windows/build.gradle.kts", "windows/native/weasel.sln",
        "windows/native/weasel.props.template", "windows/native/LICENSE.txt",
        "windows/native/UPSTREAM.json", "windows/THIRD-PARTY.md",
        "windows/scripts/package.ps1", "windows/scripts/prepare-deps.py",
        "windows/scripts/build-installer.ps1", "windows/scripts/test-installer.ps1",
        "windows/installer/ZephyrSetup.iss", "windows/installer/setup-helper.ps1",
        "docs/windows/VALIDATION.md", "docs/windows/1.4.2-short-prompts.md",
        "docs/ai/models-example.json", "docs/ai/evaluation-cases.json",
        "docs/ai/submodules.lock", "tests/corpus/gold.tsv",
    ]
    missing = sorted(set(required) - set(files))
    key_pattern = re.compile(rb"sk-(?:(?:proj|or-v1)-[A-Za-z0-9_-]{24,}|[A-Za-z0-9]{40,})")
    private_pattern = re.compile(rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----")
    sensitive, oversized = [], []
    total = 0
    for name in files:
        path = ROOT / name
        size = path.stat().st_size
        total += size
        if size >= 100 * 1024 * 1024:
            oversized.append(name)
        # Bounded memory with overlap so a credential cannot evade detection at a chunk edge.
        tail = b""
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                data = tail + chunk
                if key_pattern.search(data) or private_pattern.search(data):
                    sensitive.append(name)
                    break
                tail = data[-512:]
    failures = {
        "Ignored files still tracked": ignored_tracked,
        "Missing/excluded required files": missing,
        "Potential credentials/private keys (paths only)": sensitive,
        "Files >= GitHub 100 MiB limit": oversized,
    }
    print(f"Publishable source/resource files: {len(files)}; {total / 1048576:.2f} MiB")
    print("By root:", dict(collections.Counter(name.split('/')[0] for name in files)))
    for label, values in failures.items():
        print(f"{label}: {len(values)}")
        for name in values[:20]:
            print("  " + name)
    failed = any(failures.values())
    print("FAIL: resolve the findings before publishing." if failed else "PASS: source publication checks passed. No files were staged or uploaded.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
