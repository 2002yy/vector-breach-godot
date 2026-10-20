# 远距对比度：数值规则与后照明原型

本文件为 #56 原型记录；后续输入接入与六角色诊断见 [续片记录](TASK_CHARACTER_CONTRAST_INPUTS_2026-10-20.md)，当前能力以 [项目状态](PROJECT_STATUS.md) 为准。

基线 main `4bd98c12ec11ff177352d0aad6b98842ebc2c5ba`，分支 `feat/character-distance-contrast-20261020`。本片继续角色优先级，不把远距提亮写入 ALBEDO，也未将原型默认接入游戏或覆盖唯一已验试玩包。

## 已开发

- `source_distance_contrast.gdshaderinc` 移植原 PS 的阈值/曝光、平均反照率色调及饱和保护、表面反照率分段曲线、视线双向 irradiance 对比度、HDR 超出 1 的部分保留、400–1400 源单位平滑距离和最大 .8 权重。输入明确为线性 HDR、表面/平均反照率、朝向/背向相机的方向 irradiance、场景单位及 fog modification。
- 原算法来源为本机 Steam manifest `2520908610273941189` 的 `csgo_character` PS combo 0（私有取证目录 `native-ps-glsl/combo-0-0.glsl`，主要公式行 1393–1715）。未把整份原着色器公开再分发。只对无效场景单位、全黑平均色分母、逆序 smoothstep 做明确有限值保护/等价改写。
- `distance_contrast_postlit.gdshader` 为开发探针的 `next_pass`：读取不透明阶段后的线性颜色，保留深度测试，不写深度，不重复叠加场景雾；`inputs_ready=false`，强度和雾参数默认 0。游戏没有附加此材质的调用，也没有面向玩家的假完成开关。
- [Godot 屏幕读取文档](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) 明确 3D 屏幕拷贝在不透明之后、透明之前；[Material 文档](https://docs.godotengine.org/en/stable/classes/class_material.html#class-material-property-next-pass) 明确 next_pass 重新绘制几何，实际顺序仍受材质、优先级和距离影响。因此原型用提前的透明优先级并验证遮挡/前景透明层，不能只凭 shader 编译就认定可用于烟雾与所有透明特效。

## 验证

本机证据 `D:/AgentGamePipeline/evidence/character-distance-contrast-20261020/`：

- Forward+ Vulkan **35 项**：26 个解析数值金标准与 9 个实际后照明阶段检查。数值读取 HDR 子视口浮点结果，覆盖 400/900/1400 距离、单位缩放、曝光开关、双向光照、HDR、低/高饱和和零/无效输入；阈值以内完全恒等。不是把 shader 文本与自身字符串比较。
- 阶段检查：远处改变已照明颜色；缺少输入、近距、无光、雾门控与强度零保持原结果；墙体遮挡不能被揭露，场景雾不重复，前景透明颜色不会被抹掉。`gpu-final/checks.json` 与对应图片留证，已查看远处开关样本。
- 完整原生 206 项，`RUN_ALL_OK` 且无 ERROR；Python 非 Blender 31 项、GdUnit 2/2、探针 GDScript lint/format、资产层/元数据/运行契约及 9 个正式 GLB、diff 检查通过。最终提交/CI 状态以本片交付收据为准。

## 尚未关闭

1. 原材质/纹理的平均反照率获取、逐片元视线方向上的地图 irradiance / 光探针输入、原 fog modification 与当前环境管线的映射尚未接齐。原型中的常量光照仅用于解析测试，不冒充三图真实光照。
2. 真实六角色/动作/武器与不同材质的远近画面对照、雾/烟雾/多角色遮挡、原引擎同灯光金标准仍待验证。
3. `next_pass` 增加几何绘制和屏幕拷贝成本。需与可提供材质 ID/光照输入的合成阶段方案比较，量化 CPU/GPU、显存与三图 70% 帧率，再确定正式接入方式。

继续取证已解出原动态参数表达式：`g_vAvgAlbedo = TextureAverageColor(g_tColor).xyz`；`g_bDistanceContrastAdjustment = F_DISTANCE_CONTRAST_ADJUSTMENT && !F_TRANSLUCENT`；有效曝光为透明材质的原值、不透明材质的 `1 - 原值`。因此数值核心接收的是原 shader 的**有效 uniform**，后续不能把 VMAT 原 exposure 不加处理直接接入。六张原颜色 VTEX 的 Reflectivity/尺寸/哈希已单列私有 `average-input-candidates.json`，均为 1024²；其与 TextureAverageColor 的最终绑定语义、逐片元方向光照及雾修改仍须核实，没有在本片默认套用。

本片完成数值核心和渲染阶段原型，**远距对比度尚未在实际对局启用**。下一执行片为原始平均反照率/方向光照数据合同与真实角色对照；发丝环境瓣、眼球远距过滤和其他 [待修项](CURRENT_PENDING.md) 继续保留。
