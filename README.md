# Vector Breach Godot

中文优先说明。This repository contains the standalone Godot prototype/migration slice for `Vector Breach`.

## 当前内容

- Godot 4.6 项目骨架
- 语义灰盒地图加载与构建
- 第一版玩家移动/碰撞校准
- 双武器骨架
  - 步枪：可学习的固定后坐/弹道节奏
  - 手枪：半自动、副武器槽位、`1/2` 切枪
- HUD、命中反馈、调试线与目标假人
- 一套可 headless 运行的最小自动化测试

## 目录结构

- `project.godot`: Godot 项目入口
- `assets/`: 预览图与静态资源
- `data/levels/`: 地图 JSON 数据
- `data/weapons/`: 武器资源定义
- `scenes/`: 场景
- `scripts/`: 运行时代码与测试代码
- `tools/run_godot_tests.ps1`: 一键运行所有 Godot 场景测试

## 环境要求

- Godot `4.6.x`
- Windows PowerShell

如果 `Godot.exe` 不在系统 `PATH` 中，可以：

- 运行测试时传 `-GodotExe <你的 Godot.exe 路径>`
- 或设置环境变量 `GODOT_EXE`

## 本地运行

在 Godot 编辑器中直接打开本目录，或使用命令行：

```powershell
Godot.exe --path C:\path\to\godot
```

主场景是：

```text
res://scenes/Main.tscn
```

## 测试

运行全部测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1
```

如果 Godot 不在 `PATH`：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -GodotExe "C:\Program Files\Godot\Godot.exe"
```

当前会依次运行这些测试场景：

- `LevelDataLoaderTestRunner`
- `WeaponSystemTestRunner`
- `GrayboxLevelTestRunner`
- `HitFeedbackLayerTestRunner`
- `MainStateFlowTestRunner`

## 当前控制

- `WASD`: 移动
- `Shift`: 冲刺
- `Space`: 跳跃
- `鼠标左键`: 主开火
- `R`: 换弹
- `1 / 2`: 切枪
- `P`: 菜单/继续
- `F`: 全屏切换
- `Esc`: 释放鼠标 / 退出全屏

## 当前定位

这是一个偏原型验证阶段的 Godot 迁移仓库，重点是：

- 把旧实现中的关卡语义、移动手感、枪械节奏迁进 Godot
- 保持结构清楚，方便后续继续扩展
- 用最小但持续可跑的测试守住核心状态流

还没有覆盖所有“手感”验证。像楼梯/坡道 traversal、peek 节奏、压枪体感，仍然需要编辑器内和真人手测补充验证。
