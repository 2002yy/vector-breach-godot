# R29：Inferno内部滑动API位移链

基线 `4e9152b9c57df1e7a9007af00d7f12fceca685c7`。R28阶段端点折线不能表达同一move_and_slide中的内部转向，本线新增只读玩家/runner，在post-step、snap或camera处理之前取得中央移动的结果，不替换原物理算法。

## 采样合同

记录get_position_delta、get_last_motion、每个slide collision的travel/remainder及接触body/shape/法线。travel为碰撞前已走位移，remainder是未完成的请求，不能把它当成路径；last_motion只代表最后一次子移动，而非总位移。语义核对[CharacterBody3D官方文档](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html#class-characterbody3d-method-get-last-motion)和[KinematicCollision3D官方文档](https://docs.godotengine.org/en/stable/classes/class_kinematiccollision3d.html#class-kinematiccollision3d-method-get-travel)。

按顺序累加碰撞travel；若已到中央移动终点，不再重复追加last_motion；若剩余位移与last_motion一致，则补真实末段；其余情况标为unreconciled。终点必须绑定记录阶段，起点绑定pre-step后位置或上一物理结束位置，不能用自洽的伪造原点通过。运动链闭合不等于完整胶囊几何清空。

真实原生墙滑夹具8断言覆盖斜向撞墙后滑动、含小法向恢复的末段、正面撞停时最后travel已包含终点；Python另拒绝非有限数据、乱序碰撞、伪终点/起点和把请求余量当实际路径。初始夹具发现约0.7mm法向恢复，按实际测量修正其纯切向假设，未改游戏算法。

## 原图两条回放

只重跑Inferno rise_00/rise_02 Current60两条原输入，物理/输入轨迹与R27逐值一致。每条120帧，分别116/112帧的位移链闭合；从起跳至首次落地的34/36帧全部闭合，共 **70/70**，各有5个接触子移动。其余12帧地面/恢复组合保持不完整，不伪造补段。

这补齐了空中内部转向观测，但未执行重建链的连续胶囊资格检查，也未分解所有恢复/移动平台路径。两条路线仍route_unproven，geometric_clearance_proven=false，不能从链闭合宣告通路通过或无穿透。

9项针对测试（含原生8断言包装）、Python格式/F和Pyright、四份GDScript格式/lint通过。原始证据 `D:/AgentGamePipeline/evidence/inferno-slide-path-20261027/`，含冻结清单、两条回放和日志；仓库保留[无坐标摘要](evidence/inferno-slide-path-20261027/summary.json)。下一步才是对已闭合链作完整身体/恢复范围审查。正式规则/原图不变，Movement-4未验收、Movement-5冻结。
