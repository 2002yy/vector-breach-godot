# CS 角色接入（2026-10-16）

用户要求：把已取得的六套 CS 角色替换到当前游戏，包括 AI 全身与玩家第一人称外观。基线 main `4a40ab3d90aa64d5f7da74e66ba0430a2a04a408`；实现分支 `feature/cs-character-integration-20261016`。本任务沿用此前提交、推送、PR 检查与合并授权。

## 已接入的运行行为

- 防守方：海豹突击队、英国特勤队、联邦特警；进攻方：凤凰战士、精英叛军、黑狼。AI 按同队名单顺序轮换三种外观，跨回合保持名单分配；训练靶也使用同一角色加载路径。
- 玩家在「游戏设置」分别选择防守方与进攻方外观，配置持久化。阵营/皮肤变化会替换第一人称的蒙皮袖子与手套。来自同套全身网格的手臂保留原 UV、原贴图与手指权重，并接入本作已有的换枪、射击、换弹、轻砍、重刺、投掷、安装、拆除时间轴。
- 六套角色统一 1.8 米，统一核心骨骼命名，重定向共享动作；步枪/手枪/刀的站立、跑动、蹲伏分别选取对应持械姿势，保留受击和死亡动作。枪和刀附着到实际手骨。蹲伏动作不再额外叠加旧视觉根节点下沉。
- 物理胶囊、部位伤害、AI 决策、经济、回合规则及地图碰撞不由新模型决定。角色头盔、背心为皮肤外观，不代表购买了对应护甲。
- 缺少本地素材时恢复项目原有角色与双手，设置中标明「本机未安装」；未知皮肤名不参与路径拼接，设置拒绝跨阵营选项。

## 素材来源与本地边界

使用已取得的 Valve CS:GO 角色社区移植包，不宣称与官方安装包逐字节相同；没有把第三方现成 SAS/Phoenix 两个 CS2 GLB 冒充六套角色。实际选用：

| 运行 ID | 包与模型变体 | 来源 |
| --- | --- | --- |
| ct-st6 | ST6 `ctm_st6.smd` | [Workshop 1931846808](https://steamcommunity.com/sharedfiles/filedetails/?id=1931846808) |
| ct-sas-officer | SAS `ctm_sas_body0_model0.smd`，带防毒面具和装备 | [Workshop 2244023490](https://steamcommunity.com/sharedfiles/filedetails/?id=2244023490) |
| ct-fbi | FBI `ctm_fbi_varianta.smd` | [Workshop 1929904271](https://steamcommunity.com/sharedfiles/filedetails/?id=1929904271) |
| t-phoenix | Phoenix `tm_phoenix.smd`，默认皮肤族 | [Workshop 2172675819](https://steamcommunity.com/sharedfiles/filedetails/?id=2172675819) |
| t-elite | Elite Crew `tm_leet_variantf.smd` | [Workshop 2125953029](https://steamcommunity.com/sharedfiles/filedetails/?id=2125953029) |
| t-blackwolf | Sabre `tm_balkan_variantj.smd` | [Workshop 2167017312](https://steamcommunity.com/sharedfiles/filedetails/?id=2167017312) |

本机源包：`D:/AgentGamePipeline/reference-assets/csgo-original-20261015`，保留 6 套原生 MDL/VVD/VTX/VMT/VTF、取得记录及 SHA-256。转换用 SourceIO 提交 `6deac3176bf0e8dd2a50038cfa1066abfa58c1f9`；共享动作与参考骨架来源记录见该目录 `support-acquisition.json`、`downloaded-defaults.json`，源为 `apich/cs2-web` 的已部署角色资源。转换使用 Blender 5.2.0。

运行素材是被 Git 忽略的 `assets/local_reference/cs_agents/`：6 个全身 GLB、12 个左右手臂 GLB（合计 112,308,164 字节）、`manifest.json`。清单记录每个产物的 SHA-256、来源、骨骼与握持坐标。原模型/贴图及其衍生 GLB 不提交到公开仓库；公开 CI 验证无素材回退路径，本机额外验证实际六套素材。

## 重建与复验

在已取得源包的机器执行（输出目录必须以 `assets/local_reference/cs_agents` 结尾）：

```powershell
& '<Blender>/blender.exe' --background --python tools/blender/convert_local_cs_characters.py -- --source '<acquired-root>' --output '<game>/assets/local_reference/cs_agents'
& '<Godot>/Godot_console.exe' --headless --path . --import
powershell -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -GodotExe '<Godot>/Godot_console.exe'
& '<Godot>/Godot_console.exe' --path . --rendering-method forward_plus --rendering-driver vulkan res://scenes/tests/CharacterVisualProbe.tscn -- --evidence-dir '<evidence-directory>'
```

转换工具按包选一个身体变体，避免多个身体重叠；把 SourceIO 两种坐标系统一到 Blender，保留原网格蒙皮；把源材质的底色与已经翻转为 OpenGL 的法线接入 PBR，不二次反转法线。SAS/其他角色核心骨架分别做别名转换，共享动画通过全局姿态旋转差与目标骨长重定向。第一人称从肘部裁出连续原网格，手腕与肘部由本作动作的实际锚点驱动，手指使用原骨骼。

本机证据根：`D:/AgentGamePipeline/evidence/cs-characters-20261016/`。`visual-receipt.json` 包含六套双手快照和经典图实际九名 AI 名单；`actors-*.png` 为五种全身动作；六套持枪/持刀、装备动作、设置与 `match-5v5.png` 为本机 Vulkan 截图。最终 Git/PR/CI 和构建交付结果写入该目录 `delivery.json`。

新增两个有实际行为的回归：跨阵营/未知配置拒绝、六套双手切换及所有动作中的手腕/肘部接触误差小于 5 毫米；六套 AI 核心骨骼、持械动作选择、蹲伏不重复下沉、胶囊不变与原模型回退。无本地素材的环境仍完整验证设置和回退。

## 已知边界

这是角色素材接入，不是整套 Valve 游戏逻辑或原生第一人称动作移植。近距离手臂使用全身模型的原贴图，纹素密度低于专用第一人称高精模型，极端姿态和手指贴合仍可继续打磨；刀、枪、C4 外形保留本作资产。自动接触检查、动作截图和测试不替代用户最终美术验收。原有 G2 人工比赛和 G3 全面战术质量验收不因此关闭。

转换初测忘记注册 SourceIO 后材质加载失败，补注册后重导；BMesh 权重容器需要显式 `keys()`，已修；视觉探针最初错把非 5v5 的重构工厂图当作 5v5，断言失败，改为实际经典图并让探针失败返回非零。黑狼明确选 `variantj`，没有沿用红帽的另一变体。GdUnit CLI 第一次因未带 `--ignoreHeadlessMode` 拒绝启动，随后使用仓库 CI 同一参数复验。


## 本机交付验证

- 完整原生套件 172/172，标记 `RUN_ALL_OK`；GdUnit4 2/2；Godot 导入、脚本类型检查和实际运行无脚本错误。新增 GDScript 已格式化；增量 GDScript lint、Python Ruff lint/format 和 `git diff --check` 通过。原有资产层、元数据、运行契约和 9 个公开 GLB 验证全部通过。
- 源码 Vulkan 探针与导出 PCK 的 Vulkan 探针各生成 39 张实际截图，均有 `CHARACTER_VISUAL_PROBE_OK`，覆盖 6 套全身/双手、持械/动作/设置和经典图 5v5。实际 Windows release EXE 正常入口 headless 300 帧 smoke 无错误。
- 私有 Windows 完整包：`D:/AgentGamePipeline/builds/VectorBreach-cs-characters-20261016/`。EXE 与 PCK、`assets/` 必须一起保留。本机所有 18 个角色 GLB 和清单已进入 PCK。
- 私有打包验收发现原有经典地图冻结校验读取原始碰撞 GLB 的 SHA-256，而 Godot 导出默认仅保留其导入场景。没有绕过或削弱校验；完整包额外携带原始 `assets/models/dustline/dustline_depths.glb`，其 SHA-256 与冻结基线一致，之后导出 PCK 的实际经典 5v5 验证通过。这属于本地打包所需文件，不将第三方地图资源提交公开库。release 模板禁止命令行场景覆盖，因此动作探针使用同版本 Godot 加载该导出 PCK，EXE 本体另验正常入口。
- 剩余下一步：用户实际试玩六套外观，针对专用第一人称网格/纹理密度与握持细节继续打磨；不以本批截图取代用户美术签核。
