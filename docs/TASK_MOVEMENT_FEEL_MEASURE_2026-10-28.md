# R34 手感线：真实玩家平地测量

本片新增 `measure_movement_feel.gd`、`movement_feel_measure.py` 和对应回归。真实实例化现有Player与WeaponSystem，在独立200×200m平地夹具中测三方案、9项动作、60/120Hz，共54项。没有修改正式Current参数、原地图几何、共享规则或资产。平地不是三图，脚本输入不是人工，候选名称不代表原版客户端等价。

在创建Player前等待三个正确物理tick；逐个样本严格检查delta、完整连续tick、冻结方案/动作顺序、合成输入时序、真实武器与FOV。停步比较前0.5秒必须已稳态；速度结果取末0.5秒实际水平velocity中位数，末段速度跨度不得超过0.001m/s，不用speed_limit读值代替实测速度。

脚点定义为当前碰撞胶囊世界中心Y减当前胶囊高度一半，避免蹲伏中心偏移冒充跳高。跳高以真实jumped样本前脚点为基准，取至首次真实grounded样本的最大脚点提升；腾空以起跳样本开始至首次落地样本结束计时。首次落地含现有Player贴地/吸附行为，不是理想抛体飞行时间；落地脚点误差均约0。时间取样量化为1/60或1/120秒，不作过零插值。

固定输入使用 `Input.action_press`/release，在物理父节点中注入；Godot的jump just_pressed在注入后的下一物理tick被Player消费，工具分别固定注入与消费时序并严格核对，不能把该合成延迟解释为键盘到画面的设备延迟。`--fixed-fps`用于快速、确定性模拟，不提供真实呈现帧率或输入延迟证据。首版与严格门闸发现的输入断言失败保留于外部v1/v2，最终为v3。

三方案真实AK速度（m/s，两个频率一致，末0.5秒跨度为0）：

| 方案 | 跑 | 静步 | 蹲行 | AWP未镜 / 开镜 |
| --- | ---: | ---: | ---: | ---: |
| Current | 5.828 | 3.008 | 2.068 | 5.828 / 5.828 |
| Legacy | 5.6134 | 2.9190 | 1.8693 | 5.334 / 3.810 |
| Modern | 5.461 | 2.8397 | 1.8567 | 5.080 / 2.540 |

下表每格为60Hz / 120Hz，保持真实频率差，不以放宽容差或调默认参数凑相等：

| 方案 | 普通跳高m | 蹲跳高m | 普通腾空s | 蹲跳腾空s |
| --- | ---: | ---: | ---: | ---: |
| Current | 1.37065 / 1.34925 | 1.61870 / 1.59557 | 0.9833 / 0.9667 | 1.0833 / 1.0667 |
| Legacy | 1.20098 / 1.17240 | 1.20098 / 1.17240 | 0.6333 / 0.6167 | 0.6333 / 0.6167 |
| Modern | 1.51324 / 1.48078 | 1.51324 / 1.48078 | 0.7333 / 0.7167 | 0.7333 / 0.7167 |

普通跳两频高度差Current21.4mm、Legacy28.6mm、Modern32.5mm，仍是待裁定的离散差，不能称频率精度门槛已通过。Current蹲姿独立起跳冲量仍高于普通跳，Legacy/Modern没有独立蹲姿冲量；是否采用任一方案仍需原机与三图实际操作。

| 方案 | AK初速m/s | 松键到≤0.01m/s时间s | 松键滑行m（60 / 120） | 反向速度首次过零s（60 / 120） |
| --- | ---: | ---: | ---: | ---: |
| Current | 5.828 | 0.300 / 0.300 | 0.6694 / 0.7078 | 0.0833 / 0.0750 |
| Legacy | 5.6134 | 0.450 / 0.450 | 1.0135 / 1.0497 | 0.0833 / 0.0833 |
| Modern | 5.461 | 0.3833 / 0.3833 | 0.7810 / 0.8178 | 0.1333 / 0.1250 |

同方案两频初速完全一致，三方案初速不同；因此这些结果比较的是实际各方案/装备组合，不是统一初速的纯摩擦常数。报告另保留反向净位移和最大前滑距离，不能把过零时的净位移当整个前滑距离。

本机证据：`D:/AgentGamePipeline/evidence/movement-three-lanes-20261028/feel/rate60-v3/`、`rate120-v3/`、`comparison-v3.json`及`checks.json`。11项回归、Ruff/格式/Pyright/GDS格式与lint通过，来源绑定11份直接运行时文件；每次verify重新读取原始轨迹、核对来源并重算已保存metrics，不信任摘要字段。来源变化须新版本重测。

```powershell
python tools/movement_feel_measure.py run D:/AgentGamePipeline/evidence/movement-three-lanes-20261028/feel/new-rate60 --project D:/AgentGamePipeline/repos/VectorBreach-godot --godot D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --rate 60
python tools/movement_feel_measure.py verify D:/AgentGamePipeline/evidence/movement-three-lanes-20261028/feel/rate60-v3 --project D:/AgentGamePipeline/repos/VectorBreach-godot
```

下一步依据该表进行三图人工对照，记录急停可控性、跳跃/蹲起、开镜和舒适度；原机同条件实测、空中变向轨迹、落地伤害/相机、复杂台阶/动态支撑仍待补。所有human_review保持pending，Movement-4未验收、Movement-5冻结。
