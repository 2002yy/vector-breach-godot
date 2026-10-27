# R30：Inferno API位移链完整胶囊查询

基线 `11b236202d27cf74eb1c252b94bee1577139c339`。沿用R29 `rise_00/rise_02 Current60` 原回放，重新验证R27来源、物理/输入逐值等价、R29探针和当前runtime/原图身份，不新增玩法回放或改正式规则。

## 执行与身体合同

新增 `tools/inferno_chain_capsule.py`、`ChainCapsuleSweep.gd` 和 `audit_inferno_chain_capsule.gd`。逐帧重新检查中央移动起点与上一物理结束/pre-step结束、终点与post-step/snap之前真实记录的绑定，按collision travel顺序查询，只有残余等于last_motion才补末段。请求remainder不进入路径。起跳至首落70帧全部闭合，重建78段实际位移，其中68段为last_motion末段。另对同帧中央起终点作70条比较弦查询；比较弦不冒充实际路径。

原角色场景胶囊半径0.4m，各来源帧高度约1.8m、均未蹲伏，局部offset为0。验证器明确拒绝矮胶囊/蹲伏数据继续使用0 offset；不扩大为任意姿态支持。原生验证actor scene SHA、实际CapsuleShape3D与局部offset，并绑定原图碰撞/导入/layout/level SHA、Godot hash、生产/作者runtime与新探针SHA。查询mask=1、margin=0.001m，不排除任何地板/碰撞体、不缩身体；每段初末重叠检查+连续cast_motion+接触normal/body/shape记录。重叠、接触、非零API depth均保守保留，不把接触normal误作穿透深度或恢复路径证明。

薄墙夹具8断言证明端点空但途中薄墙可被连续cast捕获、支撑面与墙面分类、不忽略初始重叠、清空末段和非零depth撤权。Python7项包括原生包装，并拒绝错起终点、空中未闭合、矮/非有限高度及无界JSON精度容差。

## 实际结果

| Current60点 | 空中帧 | 实际段/末段 | 查询清空段 | 含重叠段 | 支撑cast/墙cast | 非零depth段 | 非清空比较弦 | 区间外未闭合帧 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| rise_00 | 34 | 38/33 | 28 | 10 | 1/2 | 8 | 6 | 4 |
| rise_02 | 36 | 40/35 | 29 | 11 | 0/1 | 8 | 7 | 8 |

最终执行 **748次碰撞API查询**，共78实际段和70比较弦；与格式化前同输入的748次诊断数值结果一致，前版清单/报告/日志保留为`*-before-format`，总计1496次查询调用，均不算玩法回放。57段严格查询清空、21段含初始或末端重叠，3段cast命中墙/顶面，1段cast命中支撑面。没有任何非清空比较弦帧因内部转向变成全部实际段清空，旧墙命中在对应实际travel中仍存在，不能归因为弦线假阳性。接触段和重叠段可同时计数。

接触位置范围：两点tick12起跳时从支撑转为墙面邻域，tick27/28/29侧碰邻域（rise_02另延续tick30），首落分别tick45/47支撑邻域。query_contact的法线只分类该次rest查询返回的接触，不能穷举同一聚合碰撞体全部三角面；初末重叠未被排除。API recovery depth非零的16段均保持unproven，实际恢复轨迹、其他pre/post-step与snap位移、区间外12个地面/恢复未闭合帧也未获资格。没有证明穿透，也没有证明完整身体清空。

两点继续 `route_unproven`、`geometric_clearance_proven=false`。Movement-4未验收、Movement-5冻结。下一片转向已有清空通道的Inferno rise_03/04作有界原目标输入，不重复这两条已知接触路径查询矩阵。

证据目录 `D:/AgentGamePipeline/evidence/inferno-chain-capsule-20261027/`：最终`chain-v1.json`、`sweep.json`、`validated-summary.json`和`native.log`；仓库保留[无坐标摘要](evidence/inferno-chain-capsule-20261027/summary.json)。Python格式/F/Pyright零错误，三份GDScript格式/lint通过。全套验证由R30整合入口统一记录；本线未改旧工具、正式玩法/地图/资产/包或全局状态文档。
