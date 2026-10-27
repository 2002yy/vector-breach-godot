# R31 作者支撑候选的物理边界回归

基线 `a0c40e6`；冻结 `ModernSnapSupportPlayer.gd` 及其父链，新增独立小物理世界和 Python CI 入口。无 MAP/原图资源加载，无正式玩法或作者候选修改。

Godot 4.7.1 headless 在 60/120Hz 共 **124 条断言通过**。真实旋转盒子的垂直射线命中约 60 度法线，连续物理步骤不能产生贴地或落地事件。使用正式半径 0.4m 的胶囊，在台沿附近低顶下保持 1.2m 蹲姿并获得真实支撑；抬头查询确认 1.8m 站姿会碰顶，离开顶棚和台沿后恢复站姿并失去支撑，落地事件总计仍为一次。

Current、Legacy、关闭控制、真实 Area 水体/梯子各有候选开启/关闭的成对步骤比较：最终位置、速度、贴地状态、落地次数逐值一致，且没有尝试作者支撑。额外验证空中关闭、重新开启落地、已支撑时关闭，落地事件不重复。水/梯子通过真实传感器重叠进入，不手工设环境布尔值。

CI 入口 `tools/tests/test_movement_support_boundaries.py` 匹配现有 `test_m*.py` 发现规则，启动实际 GDScript 测试，检查固定成功断言数、退出码及脚本/引擎错误；无 Godot 时显式 skip，CI 应提供 `GODOT_BIN`。本机该 Python 测试 1/1、Ruff 格式/lint、Pyright 零错误、GDScript 格式/lint 通过。原始 native 输出保存在外部 `D:/AgentGamePipeline/evidence/support-boundaries-20261027/native.log`。

初跑修正两项夹具设置：Legacy 应使用有效标识 `legacy_16`；脱离顶棚的中心位置需避开完整胶囊半径。最终重跑覆盖真实斜面射线命中及正式半径。没有发现候选缺陷，不创建修复候选。

本结论仅为上述有界物理回归。不能替代实图通路、原冻结输入、全局采用、原机/人工、AI/整场或 FPS 门槛；Movement-4 和正式采用状态保持。下一片继续主任务的 Inferno 有界输入验证。
