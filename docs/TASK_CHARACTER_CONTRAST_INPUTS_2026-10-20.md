# 角色远距对比度：原输入与真实角色诊断

基线 main `2e0187874c500004ac517bab7cfd9d625f5024eb`（#56 已合并），分支 `feat/character-contrast-inputs-20261020`。承接 [数值与后照明原型](TASK_DISTANCE_CONTRAST_2026-10-20.md)，按用户要求继续开发，不等待 CI。

## 实现

- `tools/prepare_character_contrast.py` 在核对 18 原模型哈希后，从原颜色 VTEX 的版本 1 DATA 读取原始 Reflectivity 浮点值/尺寸/哈希，连同完整原 VMAT 保存为新的私有 `source-character-contrast-inputs.json`，共 30 种唯一材质。预检全部完成才写新文件；拒绝覆盖，不改原模型、纹理或既有旁存文件。
- 按原动态表达式计算有效参数：不透明曝光为 `1 - VMAT 原值`，透明曝光保持原值；专用调整为 `F_DISTANCE_CONTRAST_ADJUSTMENT && !F_TRANSLUCENT`。专用调整关闭仍保留原全局对比度规则，不能错误关闭整个效果。
- `SourceCharacterContrast.gd` 只供诊断调用，要求明确接受平均色候选、有限参数和三组 SH1 系数。缺少数据/无效上下文移除自身通道；重复绑定复用；不覆盖其他 next_pass。游戏没有调用此绑定器。
- 后照明 pass 逐片元读取原颜色纹理和原 UV，支持原引擎 SH1 后备规则 `dot(coeff, vec4(view_direction, 1))` 的双向 irradiance。原眼球/湿润/顶点颜色引入的附加反照率变化尚未全部合入该 pass，不能称表面反照率完整等价。
- 真角色近距检查发现恒等重绘仍会改变少量轮廓像素：屏幕拷贝已含抗锯齿覆盖，重新绘制轮廓产生差异。现在对 400 源单位以内、零强度/雾及无效单位直接 discard，不重画已有结果。修后六角色 8m 前后均为 0 个变化像素。

## 证据与边界

本机证据：`D:/AgentGamePipeline/evidence/character-contrast-inputs-20261020/`。

- Forward+ Vulkan `gpu-final/checks.json` **38 项**：保留原 26 数值金标准和 9 阶段检查，新增 SH1 与独立双向常量光照一致、纹理参与表面反照率、纹理与常量结果有别三项。
- `actual-models/checks.json` 六角色在 8/22/40m 的 **18 组 / 36 张**开关对照；正交相机保持构图大小，以隔离距离规则。原贴图、UV、曝光、SH1 绑定、重复调用、无效输入清理和外来 pass 保护均有断言；六角色分别绑定 4/4/5/4/4/3 种材质。已查看六角色远距对照拼图与精英角色原图，没有据此签核完整美术等价。
- 完整原生 **206 项 / RUN_ALL_OK** 且无 ERROR，Python 非 Blender **37 项**，GdUnit **2/2**，Ruff、GDScript 格式/lint、资产层/元数据/运行契约及 9 个正式 GLB 检查通过。交付提交/PR 写入本机最终收据；不以旧提交绿色结果替代新头 CI。
- 原取证依据仍为 Steam manifest `2520908610273941189` 的私有 shader，与 pinned VRF `54279ec226cc3e1c561b10f11f0f5e879b981e6e` 的 Texture DATA 解析。VRF 的动态求值仍有 TODO；Reflectivity 与 `TextureAverageColor(g_tColor)` 的最终引擎绑定**尚未证实**，因此明确标为 `vtex-reflectivity-candidate`，必须显式接受才能诊断绑定。
- SH1 系数是测试输入，不冒充三图实际光探针。地图 lighting-volume 分支、真实 FogModificationAmount、动作/烟雾/多角色/明暗背景、原引擎同灯光金标准和性能仍待验证。

实际对局保持关闭；唯一已验试玩包不变。下一执行片：恢复三图原方向光照/探针输入，确认平均色绑定及雾参数，再评估正式合成方案与成本。发丝环境瓣、眼球远距过滤和其他 [当前待修项](CURRENT_PENDING.md) 仍保留。

工作树仅保留四个既有 `.import` 改动，不纳入本片提交；未修改关卡 JSON、碰撞/路网、移动/武器或比赛规则。CI 只在推送后记录当时状态，不等待完成；未合并前不称已进入 main。
