"""Stage verified support beside an existing export; never switches an entry."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil

from plan_playtest_delivery import payload

RUNTIME = {"VectorBreach.exe", "VectorBreach.pck", "VectorBreach-radar.pck"}


def guide(head: str) -> str:
    return (
        "矢量突袭 · 本地候选试玩说明\n"
        f"运行时源码提交：{head}\n"
        "普通入口：在本目录运行 VectorBreach.exe。\n"
        "可选环境入口：在本目录运行 角色环境候选.cmd；保留candidate-inputs与assets支持目录。\n"
        "三张原版地图；默认Current移动，Movement-5菜单未放行，环境候选默认关闭。\n"
        "包含AI闪光距离/朝向/遮挡规则、C4回收路径成本选举及真实几何雷达。\n"
        "候选已导出并绑定文件身份；未将旧包测试成绩继承为本包验收。\n"
        "完整双入口、连续人工三图、正式18场与逐图70%帧率仍待验收；C4长等待仍待查。\n"
        "本目录为未激活候选；系统桌面入口尚未更新。版本与文件身份见build-info.json。\n"
    )


def prepare(old: Path, candidate: Path, receipt: dict) -> dict:
    if old.resolve() == candidate.resolve():
        raise ValueError("Distinct old and candidate directories required")
    info = json.loads((old / "build-info.json").read_text(encoding="utf8"))
    if set(receipt.get("artifacts", {})) != RUNTIME:
        raise ValueError("Missing runtime artifacts")
    if not receipt.get("runtime_sources") or not receipt.get("runtime_source_head"):
        raise ValueError("Missing source receipt")
    entries = {}
    for name, row in info["files"].items():
        if name not in RUNTIME and name != "build-info.json":
            entries[name] = dict(payload(old, name, row), action="copy_support")
    for name, row in receipt["artifacts"].items():
        entries[name] = dict(payload(candidate, name, row), action="keep_runtime")
    content = guide(receipt["runtime_source_head"])
    raw = content.encode("utf8")
    entries["试玩说明.txt"] = dict(
        action="generate_guidance",
        content=content,
        bytes=len(raw),
        sha256=hashlib.sha256(raw).hexdigest(),
    )
    required = {
        "角色环境候选.cmd",
        "assets/local_reference/dustline/de_dust2_original.glb",
    }
    required.update(
        f"candidate-inputs/{key}/bundle.json" for key in ("dust2", "mirage", "inferno")
    )
    if not required.issubset(entries):
        raise ValueError("Missing complete support")
    actual = {
        p.relative_to(candidate).as_posix() for p in candidate.rglob("*") if p.is_file()
    }
    if actual != RUNTIME:
        raise ValueError(
            "Candidate must contain only the three fresh runtime artifacts"
        )
    return dict(
        schema=1,
        runtime_source_head=receipt["runtime_source_head"],
        runtime_source_sha256=receipt["runtime_source_sha256"],
        files=entries,
        activation_allowed=False,
    )


def stage(candidate: Path, plan: dict) -> None:
    # Check every destination before any copy; refuse overwrite or path escape.
    for name, row in plan["files"].items():
        target = candidate / name
        if not target.resolve().is_relative_to(candidate.resolve()):
            raise ValueError("Escaping destination")
        for part in [target, *target.parents]:
            if part.is_symlink() or part.is_junction():
                raise ValueError("Reparse destination")
            if part == candidate:
                break
        if row["action"] != "keep_runtime" and target.exists():
            raise ValueError("Support destination exists")
    if (candidate / "build-info.json").exists():
        raise ValueError("Metadata destination exists")
    for name, row in plan["files"].items():
        if row["action"] == "generate_guidance":
            with (candidate / name).open("xb") as dst:
                dst.write(row["content"].encode("utf8"))
        if row["action"] == "copy_support":
            source = Path(row["source"])
            payload(source.parent, source.name, row)
            target = candidate / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open("rb") as src, target.open("xb") as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
        payload(candidate, name, row)
    metadata = dict(
        kind="complete_unactivated_playtest_candidate",
        runtime_source_head=plan["runtime_source_head"],
        runtime_source_sha256=plan["runtime_source_sha256"],
        files={
            name: {k: row[k] for k in ("bytes", "sha256")}
            for name, row in plan["files"].items()
        },
        activation_allowed=False,
        default_movement="current",
        movement5_menu_enabled=False,
        environment_candidate_default=False,
        acceptance="Support identity verified; normal EXE dual-entry acceptance pending",
    )
    with (candidate / "build-info.json").open("x", encoding="utf8") as stream:
        json.dump(metadata, stream, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("old", "candidate", "receipt", "plan"):
        parser.add_argument(argument, type=Path)
    parser.add_argument("--stage", action="store_true")
    args = parser.parse_args()
    result = prepare(
        args.old, args.candidate, json.loads(args.receipt.read_text(encoding="utf8"))
    )
    with args.plan.open("x", encoding="utf8") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
    if args.stage:
        stage(args.candidate, result)
    print(
        "COMPLETE_SUPPORT",
        len(result["files"]),
        "staged" if args.stage else "plan_only",
    )
