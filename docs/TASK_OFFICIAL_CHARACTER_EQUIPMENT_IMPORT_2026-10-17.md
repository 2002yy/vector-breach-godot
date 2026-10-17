# 官方人物与装备导入执行契约

用户明确要求完成原版资源导入，保留项目现有资产。基线 main `71eeeb444abba189914e30b5002e26820ef7eebd`，分支 `feature/official-character-equipment-import-20261017`，开始时工作区干净。前序性能与整理 PR #42–44 已合并，运行候选 `8a11e49` 完整原生 179 项通过。

私有官方来源：app 730 / depot 2347770 / manifest `2520908610273941189`。原始包与独立资源保留在 `D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016/`；此批收据、导出和失败记录在 `D:/AgentGamePipeline/reference-assets/cs2-original-equipment-20261017/`。已 CRC/SHA 验证六套真实 `agents/...` 人物、各自专用第一人称袖子/手套、AK、M4、Glock、双方默认刀、C4 等原件；`characters/...` 中同名 12 三角形占位模型不得作为正式人物导入。原始导出包含多个身体组与旧/高清武器变体，运行产物必须显式选择，禁止叠加造成重影。

实现范围：六套 AI 全身和玩家对应原版专用双手；第一/第三人称枪、刀；持有、丢弃和安装 C4。全部保留原 UV/贴图/蒙皮，不重新生成纹理，不覆盖现有社区转换角色或项目装备。官方资源只放 Git 忽略目录；公开代码必须无素材也可运行。游戏伤害、碰撞、经济和回合规则不由新视觉模型决定。

验收要求：握持坐标与左右手连接数值验证、六套外观切换、步枪/手枪/轻砍/重刺/投掷/换弹/安装拆除截图、AI 持械与动作、C4 拾取/安装/倒计时交互；焦点回归、完整原生、GdUnit、lint/资产政策、源码与导出包 Vulkan 验证；提交推送、精确头 CI/无未解决审阅、合入 main、可玩包与收据。原版动作图仍在依赖盘点，不能把模型附带的 inventory/tools_preview 动作冒充完整第一人称作战动作；适配时间轴与原生片段需逐项注明。

已接入：六套全身、十二只专用手臂、M4A1-S / AK-47 / Glock、双方默认刀、手持与地面 C4，共 25 个私有 GLB。设置选择双方外观，AI 轮换同队三套，购买页使用原模型实际渲染图片。旧社区角色 18 个 GLB 与项目装备保留，官方资源缺失时回退；枪械标注“外观”，项目伤害、弹量、价格不变。

## 复用步骤和边界

取得沿用 [官方地图手册](CS_OFFICIAL_MAP_ACQUISITION.md) 的固定 manifest、范围下载与 CRC/SHA 校验。私有 `cs2-original-equipment-20261017/` 中 `seeds.json`、`prepare_equipment_ranges.py`、`resource-ranges-round*.json`、`loose-resource-receipt.json` 保存 19 个根资源和 260 个依赖；只证明视觉闭包与三个动作图根文件，不证明完整动作图依赖或完整 depot。

Source2Viewer 20.1 命令：`-i <vmdl_c> --game <gameinfo.gi> -o <目录> -d --gltf_export_animations --gltf_export_format gltf --gltf_export_materials --gltf_textures_adapt`。动画选项用于保留蒙皮，正式人物选 `agents/`，不用 `characters/` 占位模型。完整视觉源在 `exports-final`；失败尝试保留。

Blender 命令：`--background --python-exit-code 1 --python tools/blender/convert_official_cs_assets.py -- --source <exports-final> --motions <csgo-original-20261015> --output <assets/local_reference/cs_official>`。装备使用 `convert_official_cs_equipment.py`；购买图片使用 `render_official_loadout_previews.py`。输出拒绝覆盖已有文件，重新转换先归档。分离第三人称与原生 `firstperson_*` 组；武器选高清组避免叠加；握持以真实腕部坐标和 C4 边缘测量。原 UV、贴图、蒙皮保留。

枪械原生 reload/shoot 按项目时长播放；身体战斗动作重定向，刀具、投掷、安装拆除继续使用已有手部时间轴。Source 2 材质适配 Godot PBR，C4 屏幕适配真实倒计时，未称为完整原版动作图或着色器移植。

## 失败、修复与验证

进攻方身体形态键曾未随基础网格转向，导致骨架与身体错位；基础变换、归一化和共享手臂腕部转换现在均使用 `shape_keys=True`。Blender 回归覆盖 Basis/Corrective、手臂裁切与腕部转换、真实 GLB 导出再导入。本批十二只专用手臂源网格没有形态键，审查补丁不改变其产物。

弹匣检查曾读到 0.04 秒混合开始前的旧姿势；`seek` 不推进混合时钟。测量前推进 0.1 秒结束混合，仍要求真实 `clip` 骨骼位移超过 2 厘米：CT 约 0.29 米、T 约 0.47 米。没有放宽断言或修改运行时。

候选 `df99c956` 焦点 2/2、完整原生 12 套件 180 项 `RUN_ALL_OK`、GdUnit 2/2、资产三类约束及 9 个公开 GLB 检查通过；Tests `39044688245`、Windows 导出与冒烟 `39044688244` 成功。审查补修腕部形态键后重新验证精确头 CI/审查；运行代码和本批私有产物未改变，复用完整运行回归和 Vulkan 画面，不重复同一完整运行套件。

证据目录 `D:/AgentGamePipeline/evidence/official-character-equipment-20261017/` 保存日志、`visual-morph-fixed` 43 张截图和最终交付收据。新包目录目标 `C:/Users/Zhang/Games/VectorBreach-official-assets-20261017/`，需保留整个目录。PR #45 的最终提交、合并、包和实测以 `delivery.json` 为准；未完成项不作为已交付。下一片是完整原版作战动作图依赖和动作接入，不关闭最终人工美术、全图性能与长局平衡验收。
