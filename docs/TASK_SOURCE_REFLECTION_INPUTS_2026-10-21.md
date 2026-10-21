# 原反射数组：压缩块、七级 mip 与盒投影验证

分支 `feat/source-reflection-inputs-20261021`，基线为 #64 合并后的 main `290da7628575dc6e2ed679d44dd3f4148d6d7b30`。#64 精确头 `d7f460d` 的 Tests `39595482197`、Windows export/smoke `39595482274` 已成功；不等待后续 main push CI 开始本片。四个既有 `.import` 状态不提交；本片不改地图、碰撞、路网、规则和原资源。

## 本片实现

`prepare_source_reflections.py` 校验关卡权威 VPK 哈希后，从包内重新提取原 cubemap 数组和实体 lump。`SourceReflectionDump.cs` 通过原 VRF API 解开存储压缩，保存 **BC6H 块本身**，没有重压缩、降成 RGBA8、生成新 mip 或修改原文件。七级原 mip 为 256→128→64→32→16→8→4，不假设存在 2×2/1×1。原 `.vtex_c`、实体、每级哈希与整份块哈希随私有证据保存；输出采用临时目录完成后改名，拒绝覆盖既有结果。

`SourceReflectionTexture.gd` 检查 schema、尺寸、六面顺序、各级步长和哈希，将 mip-major 数据重排为每个数组层连续的 mip 数据。通过 `RenderingDevice` 创建 **BC6H-UFLOAT / CUBE_ARRAY / 七级 mip**，用 `TextureCubemapArrayRD` 供着色器采样。创建失败/无 RenderingDevice 时不安装纹理；支持取消、显式释放和销毁时清理。没有借用普通 CubemapArray 的完整 mip 链来补造两级数据。

原 `env_combined_light_probe_volume` 的 origin、yaw、bounds、edge fade、priority、handshake、array index 与完整参数保留。数组层逐一覆盖 0…N−1；不把 LPV 的三维片布局套在 cubemap 上。盒投影按**原探针局部原点**计算，不能改成盒中心。Source 坐标下的 yaw/平行轴处理与越界拒绝有 CPU/GPU 对照；尚未接游戏世界坐标选择与混合。

工具编译复用 `build_source_lighting_bridge.py --source tools/native/SourceReflectionDump.cs`；不传 `--source` 的旧 LPV 编译方式保持有效。原包、桥接运行时和原反射数据不公开提交。

## 三图 GPU 证据

私有目录 `D:/AgentGamePipeline/evidence/source-reflection-inputs-20261021/`，各图 `*-final/reflection.json` 和 `*-final-proof/`：

| 图 | 原 cube 层 | 原 mip | CPU/GPU HDR 采样 | 原坐标盒投影 | 展示 PNG |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dust II | 43 | 7 | 630 | 387 | 9 |
| Mirage | 58 | 7 | 630 | 522 | 9 |
| Inferno | 116 | 7 | 630 | 1044 | 9 |

每图选首/中/末三个 cube，六面 × 七级 mip × 五个非对称像素位置，与 VRF 独立 CPU HDR 解码比较；不是只看中心色。共 **1890** 个颜色样本，实测 `abs(gpu-cpu)/max(1,cpu)` 最大小于 **5e-8**。样本最高值约 1.44–1.84，保留 HDR 超 1 信息。全部 **217** 个原探针各取三位置/三方向，共 **1953** 组盒投影，最大分量误差小于 **0.000977**（HDR viewport 半精度读回）。

每图三层 × mip 0/3/6 共九张等距柱状图；仅展示用 Reinhard 映射，不回写输入。已查看三图 mip0 全景，天/地与原场景细节可辨。每图另通过上传取消/无显式释放销毁检查，原持有纹理随后继续完成采样，日志无脚本/资源错误。完整最终原生/Python/GdUnit、格式/静态导入、精确提交与 PR/CI 状态见该目录 `delivery.json`，不能用旧头通过代替新头。

CPU/GPU/API 参考：[固定版 VRF Texture](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/ValveResourceFormat/Resource/ResourceTypes/Texture.cs)、[environment](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Shaders/common/environment.slang)、[Godot TextureCubemapArrayRD](https://docs.godotengine.org/en/stable/classes/class_texturecubemaparrayrd.html)、[RDTextureFormat](https://docs.godotengine.org/en/stable/classes/class_rdtextureformat.html)。GPU 使用 Godot 4.7.1 Forward+ Vulkan；不是原引擎实机同灯光参考。

最终本地候选：完整原生 **208 项 / RUN_ALL_OK**、Python 非 Blender **56 项**、GdUnit **2/2**、C# 桥接编译、GDScript format/lint、Python Ruff、导入、三项资产策略与 `git diff --check` 通过；18 原模型哈希不变。失败证据保留：早期 probe 类型推断错误、损坏元数据比较引发脚本错误、PREDELETE 内调用自身方法错误，均已修复并重跑对应正负对照及完整套件；不能以失败日志中的 PASS 字样计数。

## 验证入口与剩余

`res://scenes/tests/SourceReflectionGPUProbe.tscn -- --input <reflection.json> --evidence-dir <新目录>` 为显式诊断入口。新增无私有资产的 schema/损坏输入测试已纳入 Windows/Linux 原生套件；Python 测试覆盖缺级、坏哈希、错步长/面序、盒原点/偏心盒、yaw、平行轴、越界和数组索引。不能把负输入函数意外报 SCRIPT ERROR 后返回空值当作测试通过。

本片完成原始输入桥接，**没有接入正式角色环境着色、发丝第二瓣或桌面包**。下一片接游戏空间对齐、优先级/边界混合、反射归一化 SH/BRDF 和显式双瓣采样；当前原数据已保存，不能以 LPV、EMISSION 或 Godot 默认环境提亮替代。眼球连续运动/跨 GPU、软法线/切线、加载、C4/观战、AI、最新头 18 场、三图人工试玩及 70% FPS 要求仍保持未验收。
