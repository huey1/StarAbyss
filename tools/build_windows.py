#!/usr/bin/env python3
"""Star Abyss Windows x64 release build pipeline.

Python port of tools/build_windows.ps1. The PowerShell original requires
PowerShell 7 (`#Requires -Version 7.0`, `ProcessStartInfo.ArgumentList`), and this
machine only has Windows PowerShell 5.1, so the pipeline is expressed in Python and
runs through the `py` launcher.

Behaviour matches build_windows.ps1 stage-for-stage:
  * engine version and export-template version must be identical;
  * export runs with APPDATA redirected into the project so the user's real Godot
    editor settings are never touched;
  * a stage fails on non-zero exit or on SCRIPT ERROR/SHADER ERROR/ERROR/FAIL/WARNING
    lines (a small documented allowlist covers environment noise);
  * the final PCK is functionally smoke-tested with the same-version editor runtime
    (`--main-pack` + external fixture), and the real release EXE is launched
    separately for a normal-start check;
  * BUILD_INFO.json records which checks really ran;
  * the package directory is checked for unexpected files, then hashed and zipped.

Additions over the original:
  * `--install-templates TPZ` extracts the matching official template out of the
    official .tpz archive, so a clean machine needs one command (see below);
  * `--clean` removes only this pipeline's own outputs, never a directory tree.

Usage:
    py tools/build_windows.py --install-templates D:\\game\\downloads\\Godot_v4.7.2-stable_export_templates.tpz
    py tools/build_windows.py                 # export + package + smoke + zip
    py tools/build_windows.py --pack-only     # PCK only (diagnostic)
    py tools/build_windows.py --skip-smoke --no-zip
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

DEFAULT_GODOT = r"D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe"
EXPECTED_ENGINE_PREFIX = "4.7.2.stable"
# Directory name Godot uses for template lookups: <version-without-hash>.
TEMPLATE_VERSION_DIR = "4.7.2.stable"
PRESET_NAME = "Windows Desktop"
PACKAGE_NAME = "star_abyss_windows_x64"
EXE_NAME = "StarAbyss.exe"
PCK_NAME = "StarAbyss.pck"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GAME_PATH = PROJECT_ROOT / "godot"
TEMPLATE_DIR = PROJECT_ROOT / ".local" / "export_templates" / TEMPLATE_VERSION_DIR
TEMPLATE_EXE = TEMPLATE_DIR / "windows_release_x86_64.exe"
# Standard Godot template location, used only if the preset does not pin a custom template.
APPDATA_PATH = PROJECT_ROOT / ".local" / "appdata"
STANDARD_TEMPLATE_EXE = APPDATA_PATH / "Godot" / "export_templates" / TEMPLATE_VERSION_DIR / "windows_release_x86_64.exe"
BUILD_ROOT = PROJECT_ROOT / "builds" / "windows"
PACKAGE_PATH = BUILD_ROOT / PACKAGE_NAME
DIAGNOSTICS_PATH = PROJECT_ROOT / ".local" / "export-diagnostics"
ZIP_PATH = BUILD_ROOT / f"{PACKAGE_NAME}.zip"

EXE_PATH = PACKAGE_PATH / EXE_NAME
PCK_PATH = PACKAGE_PATH / PCK_NAME

# Engine lines caused by this sandbox / redirected APPDATA, not by the game.
IGNORED_ERROR_LINES = (
    "Failed to read the root certificate store",
    "Error saving editor settings to",
    "Can't save resource to empty path",
    # Software renderer / dummy audio driver notices on machines without a GPU context.
    "Your video card driver does not support any of the supported Vulkan",
    "Unable to initialize Vulkan",
)

ERROR_PATTERN = re.compile(r"(?im)^\s*(SCRIPT ERROR:|SHADER ERROR:|ERROR:|FAIL:|WARNING:)")
SMOKE_MARKER = re.compile(r"EXPORT SMOKE RESULT: (\d+) checks, (\d+) failures")


class BuildError(RuntimeError):
    """A stage failed; the message is the summary printed before a non-zero exit."""


def log(message: str) -> None:
    print(message, flush=True)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def genuine_error_lines(text: str) -> list[str]:
    """Engine error/warning lines minus the documented environment noise."""
    problems: list[str] = []
    for line in text.splitlines():
        if not ERROR_PATTERN.match(line):
            continue
        stripped = line.strip()
        if any(ignored in stripped for ignored in IGNORED_ERROR_LINES):
            continue
        problems.append(stripped)
    return problems


def run_stage(name: str, executable: Path, arguments: list[str],
              working_directory: Path | None = None,
              timeout: int = 120) -> str:
    """Run one engine stage; return combined stdout+stderr, raise BuildError on failure."""
    command = [str(executable), *arguments]
    log_path = DIAGNOSTICS_PATH / f"{name}.log"
    log_file = DIAGNOSTICS_PATH / f"{name}.output.txt"
    env = dict(os.environ)
    env["APPDATA"] = str(APPDATA_PATH)

    started = time.time()
    try:
        completed = subprocess.run(
            command, cwd=str(working_directory or GAME_PATH), env=env,
            capture_output=True, timeout=timeout, text=True,
            encoding="utf-8", errors="replace",
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        code = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        output = stdout + stderr
        code = -1
        timed_out = True

    log_file.write_text(output, encoding="utf-8")
    engine_log = ""
    if log_path.exists():
        engine_log = log_path.read_text(encoding="utf-8", errors="replace")

    problems = genuine_error_lines(output) + genuine_error_lines(engine_log)
    elapsed = time.time() - started
    log(f"  [{name}] exit {code}, {elapsed:.1f}s")
    if timed_out:
        raise BuildError(f"{name} timed out after {timeout}s\n{output[-4000:]}")
    if code != 0:
        raise BuildError(f"{name} failed with exit code {code}\n{output[-4000:]}")
    if problems:
        summary = "\n".join(f"  ! {line}" for line in problems[:20])
        raise BuildError(f"{name} produced {len(problems)} error/warning line(s):\n{summary}")
    return output


def engine_version(godot: Path) -> str:
    output = run_stage("editor-version", godot, ["--version"], PROJECT_ROOT, 60)
    version = output.strip().splitlines()[-1].strip() if output.strip() else ""
    return version


def resolve_template() -> Path:
    """Return the release template the preset will actually use, or raise."""
    if TEMPLATE_EXE.is_file():
        return TEMPLATE_EXE
    if STANDARD_TEMPLATE_EXE.is_file():
        return STANDARD_TEMPLATE_EXE
    raise BuildError(
        "Missing Godot 4.7.2 release export template. Expected one of:\n"
        f"  {TEMPLATE_EXE}\n"
        f"  {STANDARD_TEMPLATE_EXE}\n"
        "Install it with (no download is performed by this script):\n"
        "  py tools/build_windows.py --install-templates <Godot_v4.7.2-stable_export_templates.tpz>\n"
        "See docs/BUILD_WINDOWS.md."
    )


def install_templates(archive: Path, force: bool = False) -> None:
    """Extract windows_release_x86_64.exe from an official .tpz archive."""
    archive = archive.resolve()
    if not archive.is_file():
        raise BuildError(f"Export-template archive not found: {archive}")
    size = archive.stat().st_size
    if size < 1 << 20:
        raise BuildError(f"Export-template archive looks truncated: {archive} is {size} bytes")
    log(f"Installing export templates from {archive} ({size:,} bytes)")
    log(f"  archive sha256: {sha256_of(archive)}")
    try:
        with zipfile.ZipFile(archive) as bundle:
            bad = bundle.testzip()
            if bad:
                raise BuildError(f"Export-template archive is corrupt at member {bad}")
            wanted = [name for name in bundle.namelist()
                      if name.startswith("templates/") and name.endswith("windows_release_x86_64.exe")]
            if not wanted:
                raise BuildError("Archive contains no templates/windows_release_x86_64.exe")
            member = wanted[0]
            TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
            if TEMPLATE_EXE.exists() and not force:
                log(f"  template already installed: {TEMPLATE_EXE}")
            else:
                with bundle.open(member) as source, TEMPLATE_EXE.open("wb") as target:
                    shutil.copyfileobj(source, target, 1 << 20)
                log(f"  extracted {member} -> {TEMPLATE_EXE}")
    except zipfile.BadZipFile as exc:
        raise BuildError(f"Export-template archive is not a readable zip: {exc}") from exc
    size = TEMPLATE_EXE.stat().st_size
    log(f"  template size: {size:,} bytes")
    log(f"  template sha256: {sha256_of(TEMPLATE_EXE)}")
    # Also mirror into the redirected APPDATA so a preset without a custom template works.
    try:
        STANDARD_TEMPLATE_EXE.parent.mkdir(parents=True, exist_ok=True)
        if not STANDARD_TEMPLATE_EXE.exists() or force:
            shutil.copy2(TEMPLATE_EXE, STANDARD_TEMPLATE_EXE)
            log(f"  mirrored to standard location: {STANDARD_TEMPLATE_EXE}")
    except OSError as exc:  # mirror is a convenience, not a requirement
        log(f"  note: could not mirror template into redirected APPDATA ({exc})")


def clean_outputs() -> None:
    """Remove only files this pipeline owns; never delete a directory tree."""
    owned = [EXE_PATH, PCK_PATH, ZIP_PATH, ZipHash(ZIP_PATH),
             PACKAGE_PATH / "试玩说明.txt", PACKAGE_PATH / "GODOT_LICENSE.txt",
             PACKAGE_PATH / "THIRD_PARTY_NOTICES.json", PACKAGE_PATH / "BUILD_INFO.json",
             PACKAGE_PATH / "SHA256SUMS.txt"]
    for path in owned:
        if path.is_file():
            path.unlink()
            log(f"  removed {path}")


def ZipHash(path: Path) -> Path:
    return Path(str(path) + ".sha256")


def write_engine_notices(godot: Path) -> None:
    """Read licence notices from the engine itself instead of hard-coding them."""
    script = DIAGNOSTICS_PATH / "write_engine_notices.gd"
    script.write_text(
        """extends SceneTree

func _initialize() -> void:
\tvar destination: String = OS.get_cmdline_user_args()[0]
\tvar license_file: FileAccess = FileAccess.open(destination.path_join("GODOT_LICENSE.txt"), FileAccess.WRITE)
\tif license_file == null:
\t\tpush_error("Cannot write Godot license notice")
\t\tquit(1)
\t\treturn
\tlicense_file.store_string(Engine.get_license_text())
\tlicense_file.close()
\tvar third_party: FileAccess = FileAccess.open(destination.path_join("THIRD_PARTY_NOTICES.json"), FileAccess.WRITE)
\tif third_party == null:
\t\tpush_error("Cannot write third-party notices")
\t\tquit(1)
\t\treturn
\tthird_party.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\\t"))
\tthird_party.close()
\tquit(0)
""",
        encoding="utf-8",
    )
    run_stage("engine-notices", godot,
              ["--headless", "--path", str(GAME_PATH), "--script", str(script), "--", str(PACKAGE_PATH)],
              GAME_PATH, 120)


PACKAGE_README = """星渊遗迹 / Star Abyss — Windows x64 试玩包

启动：完整解压后双击 StarAbyss.exe。请将 StarAbyss.pck 保持在同一目录。
本包无需安装 Godot 或 Blender。使用支持 Vulkan 的 Windows x64 PC。

WASD 移动；鼠标转镜头；左键三段剑击；E 星刃斩；Shift 闪避；Space 跳跃；Esc 暂停。
从主菜单进入两间普通房与第三间 Boss 房。普通房清场后必须选择祝福，再穿过北侧出口。
暂停、胜利和失败界面可重新开始或返回主菜单；重新开始会清空本局进度。

首次游玩请确认游戏音量与预警可读性，完整走完一局后分别尝试重开和返回主菜单。
自动化检查不能代替人工的手感、画面和音效评价。

引擎许可见 GODOT_LICENSE.txt；引擎第三方组件通知见 THIRD_PARTY_NOTICES.json。
SHA256SUMS.txt 可用于核对解压后的文件完整性。
"""


def verify_package_contents() -> None:
    allowed = {"StarAbyss.exe", "StarAbyss.pck", "试玩说明.txt", "GODOT_LICENSE.txt",
               "THIRD_PARTY_NOTICES.json", "BUILD_INFO.json", "SHA256SUMS.txt"}
    unexpected = [str(path.relative_to(PACKAGE_PATH)) for path in PACKAGE_PATH.rglob("*")
                  if path.is_file() and path.name not in allowed]
    if unexpected:
        raise BuildError(
            "Unexpected files in package directory; inspect without deleting user files: "
            + ", ".join(sorted(unexpected)))


def main() -> int:
    parser = argparse.ArgumentParser(description="Star Abyss Windows x64 release build")
    parser.add_argument("--godot", default=os.environ.get("STARABYSS_GODOT", DEFAULT_GODOT),
                        help="Path to the Godot 4.7.2 console editor binary")
    parser.add_argument("--out", default=str(BUILD_ROOT), help="Build output root")
    parser.add_argument("--install-templates", default="", metavar="TPZ",
                        help="Extract the release template from an official .tpz archive and exit")
    parser.add_argument("--force-templates", action="store_true",
                        help="Re-extract the template even if one is already installed")
    parser.add_argument("--clean", action="store_true", help="Remove previous outputs of this pipeline")
    parser.add_argument("--pack-only", action="store_true", help="Export only the PCK (diagnostic)")
    parser.add_argument("--skip-smoke", action="store_true", help="Skip gameplay/startup smoke checks")
    parser.add_argument("--no-zip", action="store_true", help="Do not produce the distributable zip")
    args = parser.parse_args()

    global BUILD_ROOT, PACKAGE_PATH, ZIP_PATH
    BUILD_ROOT = Path(args.out).resolve()
    PACKAGE_PATH = BUILD_ROOT / PACKAGE_NAME
    ZIP_PATH = BUILD_ROOT / f"{PACKAGE_NAME}.zip"
    globals().update(
        EXE_PATH=PACKAGE_PATH / EXE_NAME,
        PCK_PATH=PACKAGE_PATH / PCK_NAME,
    )

    godot = Path(args.godot).resolve()
    if not godot.is_file():
        log(f"FATAL: Godot editor not found: {godot}")
        return 2

    DIAGNOSTICS_PATH.mkdir(parents=True, exist_ok=True)
    APPDATA_PATH.mkdir(parents=True, exist_ok=True)

    try:
        if args.install_templates:
            install_templates(Path(args.install_templates), args.force_templates)
            log("PASS: export template installed")
            return 0

        if not args.pack_only:
            template = resolve_template()
        else:
            template = None

        BUILD_ROOT.mkdir(parents=True, exist_ok=True)
        PACKAGE_PATH.mkdir(parents=True, exist_ok=True)
        if args.clean:
            log("Cleaning previous outputs of this pipeline")
            clean_outputs()

        log(f"Godot:    {godot}")
        log(f"Project:  {GAME_PATH}")
        log(f"Template: {template if template else '(pack-only, not used)'}")

        version = engine_version(godot)
        log(f"Editor version: {version}")
        if not version.startswith(EXPECTED_ENGINE_PREFIX):
            raise BuildError(f"Expected Godot {EXPECTED_ENGINE_PREFIX}, got {version}")

        template_sha = ""
        if template is not None:
            template_sha = sha256_of(template)
            log(f"Template sha256: {template_sha}")
            template_version = run_stage("template-version", template, ["--version"], PROJECT_ROOT, 60)
            template_version = template_version.strip().splitlines()[-1].strip()
            log(f"Template version: {template_version}")
            if template_version != version:
                raise BuildError(
                    f"Template/editor versions differ: {template_version} versus {version}. "
                    "Install the export templates that match the editor exactly.")

        export_log = DIAGNOSTICS_PATH / "export.log"
        export_arguments = ["--headless", "--path", str(GAME_PATH), "--log-file", str(export_log)]
        if args.pack_only:
            export_arguments += ["--export-pack", PRESET_NAME, str(PCK_PATH)]
        else:
            export_arguments += ["--export-release", PRESET_NAME, str(EXE_PATH)]
        log("Exporting...")
        run_stage("export", godot, export_arguments, GAME_PATH, 900)

        if not PCK_PATH.is_file():
            raise BuildError("Export did not produce a PCK.")
        log(f"PASS: PCK exported ({PCK_PATH.stat().st_size:,} bytes)")
        if args.pack_only:
            log(f"SHA256 {sha256_of(PCK_PATH)}  {PCK_NAME}")
            return 0
        if not EXE_PATH.is_file():
            raise BuildError("Export did not produce a release executable.")
        log(f"PASS: EXE exported ({EXE_PATH.stat().st_size:,} bytes)")

        write_engine_notices(godot)
        (PACKAGE_PATH / "试玩说明.txt").write_text(PACKAGE_README, encoding="utf-8")

        smoke_ok = False
        if args.skip_smoke:
            log("SKIP: gameplay/startup smoke; this build remains unverified.")
        else:
            # Official release templates disable --main-pack / --script overrides, so the
            # final data pack is validated with the identical-version editor runtime, and
            # the real release binary is launched separately for a normal-start check.
            smoke_script = GAME_PATH / "tests" / "export_smoke_test.gd"
            screenshot = DIAGNOSTICS_PATH / "package_gameplay.png"
            output = run_stage(
                "pck-functional-smoke", godot,
                ["--main-pack", str(PCK_PATH), "--fixed-fps", "60", "--max-fps", "0",
                 "--disable-vsync", "--audio-driver", "Dummy", "--script", str(smoke_script),
                 "--log-file", str(DIAGNOSTICS_PATH / "pck-functional-smoke.log"), "--", str(screenshot)],
                PACKAGE_PATH, 600,
            )
            match = SMOKE_MARKER.search(output)
            if not match:
                raise BuildError("Release smoke did not produce its success marker.")
            checks, failures = int(match.group(1)), int(match.group(2))
            if failures:
                raise BuildError(f"Release smoke reported {failures} failure(s) of {checks} checks.")
            log(f"PASS: final PCK functional smoke under same-version editor runtime ({checks} checks, 0 failures)")
            run_stage(
                "release-normal-start", EXE_PATH,
                ["--fixed-fps", "60", "--audio-driver", "Dummy", "--quit-after", "120",
                 "--log-file", str(DIAGNOSTICS_PATH / "release-normal-start.log")],
                PACKAGE_PATH, 180,
            )
            log("PASS: real release EXE normal startup (separate from PCK functional smoke)")
            smoke_ok = True

        build_info = {
            "stage": "P7",
            "target": "Windows x86_64",
            "configuration": "release",
            "engine_version": version,
            "built_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "built_host": os.environ.get("COMPUTERNAME", "unknown"),
            "template_path": str(template),
            "template_sha256": template_sha,
            "exe_sha256": sha256_of(EXE_PATH),
            "pck_sha256": sha256_of(PCK_PATH),
            "exe_bytes": EXE_PATH.stat().st_size,
            "pck_bytes": PCK_PATH.stat().st_size,
            "pck_functional_smoke_verified": smoke_ok,
            "release_normal_start_verified": smoke_ok,
            "release_native_input_verified": False,
            "human_playtest_verified": False,
        }
        (PACKAGE_PATH / "BUILD_INFO.json").write_text(
            json.dumps(build_info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        verify_package_contents()

        hash_lines = []
        for path in sorted(PACKAGE_PATH.iterdir(), key=lambda item: item.name):
            if path.is_file() and path.name != "SHA256SUMS.txt":
                hash_lines.append(f"{sha256_of(path)}  {path.name}")
        (PACKAGE_PATH / "SHA256SUMS.txt").write_text("\n".join(hash_lines) + "\n", encoding="utf-8")

        if args.no_zip:
            log("SKIP: zip archive (--no-zip)")
        else:
            if ZIP_PATH.exists():
                ZIP_PATH.unlink()
            with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
                for path in sorted(PACKAGE_PATH.iterdir()):
                    if path.is_file():
                        bundle.write(path, f"{PACKAGE_NAME}/{path.name}")
            zip_hash = sha256_of(ZIP_PATH)
            ZipHash(ZIP_PATH).write_text(f"{zip_hash}  {ZIP_PATH.name}\n", encoding="utf-8")
            log(f"PASS: release package {ZIP_PATH} ({ZIP_PATH.stat().st_size:,} bytes)")
            log(f"SHA256: {zip_hash}")

        log("")
        log(f"Output directory: {PACKAGE_PATH}")
        for path in sorted(PACKAGE_PATH.iterdir()):
            if path.is_file():
                log(f"  {path.name:<26}{path.stat().st_size:>14,} bytes")
        return 0
    except BuildError as exc:
        log("")
        log(f"FAIL: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
