# 角色环境输入包与场景拥有者

## 基线与本片范围

分支 `feat/character-runtime-inputs-20261023`，基于 main `8f2dc7e8181a231df1f286bce8e68510a994ad7d`。#73 精确头 `4504306af964811b338364e99894c4f5805978c4` 的 Tests `39914919499`、Windows export/smoke `39914919468` 全成功且 CLEAN 后合入 main；本片继续开发，不等待新 CI。

已核对正常入口：`project.godot` 仍启动 `scenes/Main.tscn`，地图、相机和 CanvasLayer UI 直接处于根视口。`Main._apply_selected_map` 仍会实际加载选中地图；`_on_level_loaded` 使用 `_level_load_serial` 跨异步等待防止旧地图完成后覆盖，随后 `CombatSandbox.load_for_level` 重建角色；`TacticalActor._install_appearance` 安装原角色外观。因此不能把关卡诊断的子视口截图直接当成正常游戏接线，也不能声称选图加载优化已完成。

本片实现此前缺失的可重定位输入包、完整性校验和场景级加载拥有者。没有修改正常 Main/Actor、根视口、地图/碰撞、原纹理/模型或试玩包。正常入口的显式候选接线留作下一片。

## 资源包

`tools/prepare_character_runtime_bundle.py` 接受 reflection、lighting、normalization、indirect，Dust II 旧视觉另提供 alignment。它保留原 JSON 字节，复制依赖的 BC6H、LPV 浮点图集、原 BRDF 及对齐收据；逐文件记录相对路径、字节数、SHA256 和地图/VPK 身份。依赖哈希/地图关联先校验，复制后再次验证，最后发布 `bundle.json`。非空输出目录拒绝覆盖；原文件不移动、不改写。

```powershell
python tools/prepare_character_runtime_bundle.py --output <新的私有目录> --reflection <reflection.json> --lighting <lighting.json> --normalization <normalization.json> --indirect <indirect.json> [--alignment <alignment.json>]
```

本机实际准备 Dust II **8** 文件 / **412922546** 字节，Mirage **7** 文件 / **184898608** 字节，Inferno **7** 文件 / **510276476** 字节，位于 `D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/bundles/`。包内原参数、原通道与已有渲染规则的输入没有被平均色或占位图替换。它们只供本机显式候选使用，不加入 Git 或默认导出。

## 加载与生命周期

`SourceCharacterRuntimeInputs.gd` 是场景 Node，必须显式 `configure(bundle, level_data, actual_visual_root, true)` 才会加载。默认不开启。它先核对清单结构、大小/哈希、依赖覆盖和地图身份，再调用已有原反射/LPV/SH/BRDF 各自的合同校验与上传；只有整组成功，才一起发布可用适配器。并不声称所有语义校验都在 GPU 上传前完成。

- 每次切换/失败先撤销已管理角色的候选，恢复原材质，释放旧反射和临时上传；清单或后续任一输入失效都不会保留上一张图的候选。
- 异步反射上传绑定代次。`clear`、新请求和退出会让旧完成失效；上传期间实际视觉根节点被移出场景，也不能发布成功。
- `attach_character` 供同一地图/视口内的角色使用，返回已有 `SourceCharacterEnvironment` 合成对象并登记管理。调用方再把这些材质交给 SSAO 子视口拥有者绑定；两个拥有者职责不同。
- 退出场景会恢复登记角色并清理输入。重复角色/回合重建会剔除已经没有有效网格的旧登记。不是让每名角色重复加载整包。
- 清单检查可单独 `inspect`，但那不等于原生各项语义验证全部通过，更不等于允许正式启用。

文件哈希、JSON、LPV 图像拆分仍有同步工作，只有已有反射上传阶段异步。三包合计约 **1.1 GB**，没有把资源收敛当作加载提速；后续需要测预检、解码、上传与峰值内存。选图预览不能调用整包加载来代替轻量元数据。

## 验证与边界

三图 `CharacterRuntimeBundleProbe` 通过实际复制包的路径加载，并把该拥有者发布的适配器用于原六角色/两姿势/近远 SSAO 对照。旧黄金数值保留为独立参考。另检查哈希错误、地图错误、上传取消后立即重载、上传期间移走视觉根节点、拥有者退出；错误或退出后与原材质逐像素比较。

Python 包生成器有 **5** 个回归：完整复制/原文件不变、非空输出保护、损坏依赖、地图混用、路径越界。原生清单检查增加错误类型/数值、大小写重复、缺失角色键和非规范路径检查。全量与 GPU 最终结果见 `D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/audit.json`，提交/PR/精确 CI 首次快照与四个既存导入改动见 `delivery.json`。

最终三图 **72** 组角色 SSAO 对照、**18** 组墙体遮挡、**24** 组 hair/眼球跟随及原数值回归通过；哈希错误/地图错误和拥有者退出后严格像素差 **0**，过期上传及移出视觉根节点拒绝发布。三图各 **191 PNG**，共 **573 PNG**。完整原生 **208**、Python 非 Blender **80**、GdUnit **2/2**、格式/lint、编辑器导入/静态解析、三类资源合同与 diff/scope 检查通过，**18** 原模型哈希不变；没有修改冻结关卡 JSON。

下一片准备正常游戏的显式候选启动入口，将受控视口、此输入拥有者、地图加载代次和角色外观重建连接起来，并验证菜单/购买/观战的输入归属。默认启动与试玩包不会仅凭本片输入检查通过就启用候选。Source 2 原 per-view/对象掩码/切线等价、眼球时序、雾/平均色仍单列；最新头 18 场、三图连续人工试玩与逐图 70% FPS 继续待验收。
