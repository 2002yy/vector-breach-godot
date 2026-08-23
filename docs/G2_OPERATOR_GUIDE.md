# G2 操作手册 / G2 Operator Guide

更新：2026-08-23。本文是 G2（十场人工完整比赛）的唯一操作手册；规则权威见 `docs/PROJECT_STATUS.md`。

## 一键启动

在仓库任意位置打开终端，或直接双击：

```
godot\play-g2.cmd
```

等价命令（可自定义批次名）：

```
powershell -ExecutionPolicy Bypass -File godot\tools\start-g2-batch.ps1 -BatchName "G2-20260823-1"
```

启动器自动完成：开启 ffmpeg 桌面录屏（3 秒缓冲）→ 启动唯一可见 Godot 进程 → 监控并复制终局 JSON → 游戏退出后自动停止录屏并归档 → 运行校验器。

## 彩排（1 场，正式批次前必做）

1. 跑上面的一键命令，批次名用 `G2-REHEARSAL-<序号>`。
2. 游戏启动后，按菜单**黄字提示**选边（第 1 场 = T），点开始。
3. 完整打完一场：冻结购买 → 常规 12 回合内分出胜负 → 看到结算页。
4. 回到结算页后**正常退出游戏**（Esc 菜单或关窗均可）。
5. 录屏自动停止。结束后把实际用时告诉开发者，用于规划正式批次。

彩排批次校验器会报 FAIL（1/10 不足），属预期，不影响记录有效性。

## 正式批次（10 场）

1. 跑一键命令，批次名建议 `G2-<日期>-<序号>`。
2. 连续完成 10 场：奇数场选 T，偶数场选 CT（菜单黄字会自动提示，照着选即可）。
3. 每场必须：从菜单开始 → 跨过半场换边 → 合法终局 → 显示结算页。
4. 胜负与加时**顺其自然**，不作要求（边界由确定性探针补证）。
5. 第 10 场结算页显示后，保持录屏运行，正常退出游戏。
6. 结束后校验器自动运行；`G2_SESSION_PASS` 即批次通过。

## 硬性失败条件（任一出现 = 本批次作废，保留证据后重开新批次）

- 崩溃、软锁、回合无法结束、AI 永久卡死、C4 无主且不可恢复。
- 换边/新比赛状态泄漏。
- 选边与计划不符（奇 T 偶 CT）。
- 录屏中断（录屏必须从启动前到退出后不间断）。
- 使用调试控制、跳回合脚本，或期间启动其他 Godot 进程/跑自动测试。

## 产物结构

```
D:\VectorBreach\g2-evidence\<批次名>\
├── OPERATOR_CHECKLIST.md   操作清单（自动生成）
├── session.json            采集清单（进程、提交、基线、捕获记录）
├── logs\session.jsonl      事件流
├── raw\*.json              每场终局原始记录（只增不改）
├── video\session-raw.mp4   全程不间断录屏
├── aggregate.json/.md      校验汇总
└── SHA256SUMS.txt          记录哈希
```

边界探针证据（加时/胜负生命周期）位于 `D:\VectorBreach\g2-evidence\boundary-probes\`。

## 启动前自动检查（失败会直接报错停止）

- git 检出必须干净（记录的提交号才能标识被测构建）。
- 不能有残留 Godot 进程。
- 批次目录不能已存在（防覆盖证据）。
- ffmpeg 必须可用（`D:\ffmpeg\...\ffmpeg.exe` 或 PATH）。

## 常见问题

| 现象 | 处理 |
|---|---|
| `G2 must run from a clean checkout` | 先提交或暂存本地改动 |
| `Close every existing Godot process` | 任务管理器结束残留 Godot 进程 |
| `Evidence batch already exists` | 换一个批次名 |
| 校验 FAIL 但场次打完 | 保留证据，把 `aggregate.md` 的失败原因发给开发者 |
