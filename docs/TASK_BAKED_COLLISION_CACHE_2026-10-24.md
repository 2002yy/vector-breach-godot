# 三图离线碰撞形状缓存

日期：2026-10-24。独立基线 main `bbfd904fd26636106acc1de4c43c7d7fab69eb70`（#76），分支 `feat/baked-collision-cache-20261024`；不依赖尚未合并的 #75/#77 生产代码，不等 CI。

## 结果与实现范围

独立碰撞层现在可复用离线保存的 ConcavePolygonShape3D，保留原三角面、层级、变换、StaticBody3D 默认属性、隐藏规则及碰撞网格释放行为。缓存校验成功后仍将形状挂在原 MeshInstance 节点下，不把三图改写成另一套平面碰撞布局，也不改原 JSON/GLB/纹理/材质。

`SourceCollisionCache.gd` 绑定格式版本、引擎版本、原文件路径/SHA256、完整 `.import` 文件 SHA256、缓存内容 SHA256、网格路径集合与每个网格局部变换。缺失、不符、格式错误、缺少形状或 backface 属性异常整组回退到原生成流程；不会在游戏开局自动烘焙或修改源资产。仅独立且允许释放网格的碰撞层使用，来自视觉层的碰撞与 retain_collision_meshes 路径保持原实现。

`collision_build_ms` 包含校验、缓存读取或现场生成、创建并挂接碰撞体，`collision_cache` 另记命中/关闭/缺失/无效状态。`--disable-collision-cache` 仅供开发对照，不进入设置 UI。

## 三图交叉测量

Godot 4.7.1 / Forward+ Vulkan / RTX 5060 Laptop / 1600×900。每图顺序为原流程 → 缓存 → 缓存 → 原流程，每次独立进程，OS 缓存未清空；每模式两次，不是冷启动或稳态 FPS 采样。

| 碰撞完整阶段，毫秒 | 原流程两次 | 缓存两次 |
| --- | ---: | ---: |
| Dust II | 815 / 821 | 563 / 630 |
| Mirage | 238 / 232 | 165 / 141 |
| Inferno | 5504 / 5712 | 3694 / 3750 |

Inferno 两次均值从约 5.61 秒降到 3.72 秒，碰撞阶段约减少 34%。这里已包含校验与接入物理世界，不能用早期原型的 0.22 秒资源读取替代。真实开局总耗时也有记录，但首次运行/资源缓存造成明显波动，不将上述比例套到完整加载或 70% FPS。

## 正确性与证据

- 三图共 **123** 个形状、**3,265,932** 个三角面逐项精确相等；原节点变换、网格释放和碰撞层默认值一致。
- **11,725** 次射线比较命中/位置/法线，**1,467** 次玩家胶囊重叠数量比较，结果一致。
- 三图默认 Main 实际启动/选卡/开始/返回，四轮共 **84 PNG**；原流程关闭缓存、候选命中缓存；零预加载和每次最终地图只加载一次通过，已检查三张候选购买完成图。
- 新增故障回退与真实物理射线原生用例；完整原生、Python 非 Blender、GdUnit、格式/lint 与资源哈希结果见本机 `D:/AgentGamePipeline/evidence/baked-collision-cache-20261024/audit.json`。提交、PR、精确头 CI 首次快照见 `delivery.json`；不等待 CI。

执行入口：本机 `run-probes.py` / `physics.gd`，原始数据为 `measurements.json`、`physics-*.json` 及每轮 `loading.json`。计时从相同候选代码通过开发参数切换，其他行为一致；独立物理对照使用同一 Godot 物理后端。

## 生成与边界

在拥有原三图资源的本机执行：

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tools/authoring/bake_collision_cache.gd -- dustline-depths-original-local mirage-classic-local inferno-classic-local
```

产物保存在被忽略的 `assets/local_reference/collision_cache/`，三份资源共约 28.9 MB，旁有身份/哈希收据；与原文件分开，格式/引擎/源文件或导入配置变化需重新生成。缓存不提交到 Git。校验依赖原 GLB 与 `.import`，当前仅验本机源工程；**尚未验证导出 PCK 内原文件可读性及缓存分发**，不足时安全回退，不能宣称新试玩包已有优化。唯一已验证包仍为 #63，桌面启动器不变。

下一片先完成缓存的导出资源合同/包内验证，再处理场景读取与角色生成的等待和最长帧、内存；与 #75 候选及 #77 全阶段计时整合后须验证组合头。C4/观战 → AI 运动/难度 → 图形地图补全 → 最新头 18 场、人工连续三图与 70% FPS 的顺序不变。
