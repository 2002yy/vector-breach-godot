# 角色布料、皮肤与各向异性：修复及验证

用户要求修验此前只保留纹理、参数而未实现的角色专用效果。分支 `fix/native-character-shading-20261020`，增量基线 `72b752233b3d0037d78379b1f082262aa7752eb0`，承接尚未合并的 PR #52 及其前序候选。当前提交、远端检查、包哈希和桌面入口以私有 `delivery.json` 识别；本任务不关闭整场平衡、全部源材质或 70% FPS 验收。

## 已实现

- `prepare_character_shading.py` 校验已安装模型哈希，从本机原始 VTEX 定向恢复 31 张专用纹理；23 个唯一源材质保留完整 VMAT 与参数。原 GLB、原 PNG 和已有源参数旁存文件均不重写。资源继续位于被忽略的 `assets/local_reference/cs_official/`，不公开再分发。
- `SourceCharacterMaterials.gd` 为六套角色及专用双臂接入不透明 ShaderMaterial，保留原 PBR 纹理、UV、法线强度、通道、剔除与渲染顺序。实际 18 个模型的 63 条材质定义中，37 条启用专用效果；其他材质沿用已有材质。无专用资源时保留原材质，headless dummy 不安装 GPU 着色器。
- 布料使用原 `g_tMetalness` 蓝通道乘以非金属权重，恢复 Charlie/Neubelt 直接光响应以及原 sheen 强度、色调。
- 皮肤使用原 `g_tSssMask` 绿通道、`g_tDiffuseFalloff` LUT、曲率与分通道法线柔化参数，影响明暗交界的直接漫反射。不是简单增加红色或打开统一散射开关。
- 各向异性使用原 `g_tAnisoGloss` RG 两轴粗糙度、球面方向和角度参数，直接光高光随方向变化。Shader 不写 Alpha，继续使用不透明深度与阴影。

技术依据：[ValveResourceFormat 固定版本](https://github.com/ValveResourceFormat/ValveResourceFormat/tree/54279ec226cc3e1c561b10f11f0f5e879b981e6e) 的 complex/texturing/pbr 着色器通道与直接光实现，以及 [Godot spatial shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) 的 light/ATTENUATION/LIGHT_COLOR 契约。

## 验证结果

证据目录：`D:/AgentGamePipeline/evidence/character-shading-20261020/`。

- 完整原生 12 套件共 **194 项**，`RUN_ALL_OK`，无脚本或引擎 ERROR；其中新增材质参数、纹理绑定、共享资源不变及重复应用回归。Python 非 Blender 全套 **27 项**；GdUnit **2/2**。
- 新增 GDScript lint/format、Python Ruff check/format 通过；两份旧 GDScript 相对基线无新增 lint 问题（原有 199 条长行保留）；资产层/元数据/运行契约与 9 个正式 GLB 验证通过。
- 源码及独立 PCK Vulkan 均通过 **7 项 GPU 像素检查**：布料蓝通道、皮肤绿通道会改变画面；错误红通道无影响；各向异性旋转改变高光，等粗糙度旋转不变；关闭效果恢复同一新 Shader 的各向同性基线。该基线不代表旧 StandardMaterial 或原 Valve 引擎。
- 源码及 PCK 分别生成 **57 张角色画面**（原 39 张动作/双臂/对局，加 18 张三方向照明与开关对照），人工查看 FBI/黑狼布料及皮肤、第一人称袖子和换弹样本；未发现丢纹理、不透明裁切变化或异常爆亮。63/37 实际材质绑定审计在源码和 PCK 一致。
- PCK 从构建目录独立加载，三图菜单/帮助/购买/开战/死亡观战/返回流程通过，15 张留证；每图实际 9 个 AI。实际 EXE 从桌面目录 headless 启动退出 0，无 ERROR。三份原碰撞 GLB 随包附带并复核冻结哈希。

早期失败保留：首次 GDScript 类型推断报错已改为显式类型；动态向量索引触发 `OpVectorExtractDynamic is not supported yet`，改为显式分量访问后最终源码与包日志干净。`first-views*` 属于早期失败或旧 Shader 证据，最终以 `gpu-final`、`lighting-views`、`pack-*` 为准。

## 尚未关闭的源渲染差异

这是基于原通道和参数的直接光移植，不是完整 Source 2 渲染器复现：

- 环境反射/IBL 仍使用 Godot PBR，尚未移植 Source 布料环境 BRDF。
- 皮肤软法线以几何法线近似；尚未有原引擎同灯光金标准对照，也不宣称体积散射完全一致。
- 球面各向异性方向已转换模型坐标，原骨骼空间的严格等价仍待原引擎参考验证。
- `F_EYEBALLS`、`F_ANISOTROPIC_HAIR`、`F_DISTANCE_CONTRAST_ADJUSTMENT` 继续保留在运行时 pending 元数据及待验收清单。发丝边缘、高光和眼球层次不纳入本批完成项。
- 本批截图的实时 FPS 包含探针和并行 QA 开销，不是三图性能成绩。三图流程自动化也不替代人工完整比赛。

下一执行片：定向处理眼球/发丝及距离对比度，补原引擎同灯光参考，再完成角色环境光与骨骼空间等价验证。当前包为可试玩候选，独立复审和合并仍待完成。
