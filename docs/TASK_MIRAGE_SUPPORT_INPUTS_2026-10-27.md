# R30：Mirage真实首次支撑的新输入版本

基线 `11b236202d27cf74eb1c252b94bee1577139c339`。仅新增作者Python验证器、测试、此任务文档和无坐标公开摘要。正式Current/Modern、共享参数、原图、旧作者probe、原目标半径1.6m/高度容差0.18m均不改。Movement-4未验收、Movement-5冻结。

## 冻结合同

R29 Mirage原输入的真实首支撑距原目标约1.62454m，超半径24.54mm；当时向前速度约2.60088m/s。先冻结三个新输入：保持0.15s后退，向前助跑由0.2s分别增加1/2/3个1/60s刻度，起跳、空中Ctrl和Space释放一起后移，保持相对时序。三组均保持水平、垂直和真实support候选开启。终止向前输入仍为1.5s。

全部三组在60/120Hz各运行jump/no_jump/站立walk，共18次，不做选优或留出集声明。no_jump只删除Space；walk再删除Ctrl并加入Shift，所有事件时间完全配对。开始、目标、朝向、时长及原几何不变。清单在首次运行前冻结，旧清单和双频报告按SHA绑定；逐帧生产者probe、运行时、InputMap、原碰撞/地图/布局身份以及真实键盘步进由已有checked门闸核验。

## 实测结果

| 向前助跑增量 | 60Hz首落径向余量 | 120Hz首落径向余量 | 双频首落位置差 |
| --- | ---: | ---: | ---: |
| +1刻度（16.667ms） | 179.224mm | 179.357mm | 0.13351mm |
| +2刻度（33.333ms） | 373.901mm | 373.973mm | 0.07248mm |
| +3刻度（50ms） | 560.270mm | 560.279mm | 0.00954mm |

六次jump均在真正首次引擎支撑时落入原目标，12个配对控制均未到达。首落记录要求grounded_before=false、grounded_after=true、真实landed计数首次增加至1；全部trace继续核验事件增量与真实floor transition、支撑终点与实际角色位置、水平缓存和垂直候选记录。没有用下一帧或之后的到达覆盖首次落地。

三个新输入的双频首次支撑时间仍各差1/120s（8.333ms），不可称全轨迹或时刻等价。位置改善也不能外推到任意输入、边缘、台阶、移动地板或完整身体扫掠。旧输入双频首落仍失败，之后进入目标仍不算首落通过；R29原冻结输入集仍为4/6且采用NO-GO。

## 单列的新版本组合

按预声明顺序取最小输入变动的+1刻度版本，和R29未变的Dust II、Inferno双频support__jump组成 `r30_mirage_run_plus_1_other_maps_r29`。重新从原始报告计算这两图实际首次支撑及事件，绑定旧清单/报告SHA、probe/runtime/地图身份及目标字段hash；新组合首次目标落地 **6/6**。这只关闭该版本化作者输入组合的首落缺项，不替换旧输入集，不授予全局候选采用、精度等价、完整通路或发布权。

## 验证与交接

5项聚焦Python测试通过，覆盖三个有界时序、精确配对控制、目标不变、控制时序篡改拒绝、同帧事件门闸，以及组合计数保留失败和禁止全局授权、地图名称与实时producer摘要漂移拒绝。Ruff格式/F、Pyright零错误。真实Godot 4.7.1低内存headless兼容模式两次实图进程完成18次回放，原日志均有NATIVE_ROUTE_KEYBOARD_WRITTEN且无SCRIPT ERROR/ERROR；原生产者未改。完整套件由主线整合运行。

原始证据：`D:/AgentGamePipeline/evidence/mirage-support-inputs-20261027/`。`mirage-matrix-v1.json`为先冻结输入，`mirage-60/120.json`为实际报告，`validated-summary.json`为首次核验收据；最终`qualified-summary-v2.json`补充新版本组合、具名地图及实时producer绑定，旧收据保留。公开[摘要](evidence/mirage-support-inputs-20261027/summary.json)不含世界坐标。整合提交/PR与CI首查见主线交付。下一片应检查同候选下有代表性的边缘/台阶/不同姿态接触，并单列时间残差来源；正式采用仍NO-GO。
