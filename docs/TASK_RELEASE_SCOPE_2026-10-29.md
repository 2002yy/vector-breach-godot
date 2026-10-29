# R43 最新标准包交付范围核对

基线19291ac，只新增作者清单工具及测试，未复制大包、再次导出、改桌面入口或修改生产参数。

最新标准目录`D:/AgentGamePipeline/evidence/standard-release-20261029/candidate`的EXE、主PCK和固定`VectorBreach-radar.pck`可支持R42已经观察到的普通三图短时开局。旁置同名前缀的PNG/JSON是构建中间文件，已经包含在统一附包，不需要把它们逐个再交付。附包1,634,192字节绑定新主包的实际碰撞身份；不能配旧主PCK使用。

此三文件目录不具备旧桌面完整交付范围。旧包的`角色环境候选.cmd`传`-- --controlled-game`及三次`--character-bundle`，分别指向candidate-inputs/{dust2,mirage,inferno}/bundle.json。LaunchRouter选择ControlledGame，后者读取这些路径并绑定独立环境输入。新目录没有该入口、三图私有输入、试玩说明和版本收据，不能直接覆盖旧包而称可选角色/玩家及观战手臂环境入口已交付。旧assets原碰撞/缓存可能因新导出身份路径而部分可省，但这里只保守保留，未证明环境入口与加载缓存都不再依赖它们，不能作为垃圾删除。

新增`tools/authoring/plan_playtest_delivery.py`：只读旧build-info逐文件与新delivery artifacts的大小/SHA256，拒绝路径越界、重解析路径及覆盖已有输出；必须有正常三图开局证据，输出逐文件来源和动作，绝不复制或激活。旧43载荷与新三件合并为44个文件、5,539,096,805字节，其中沿用支持文件1,807,919,675字节；不包含待重新生成的build-info本身。清单保守复用旧支持文件，不代表它们已被新包运行时验收。

清单绑定R42未变生产树基线0b98bc9和开局收据头19291ac，后者不是当前R43 HEAD的包来源证明。若Dust通道修改生产材质，必须重新导出和生成附包后再规划交付。`stage_allowed=false`明确阻止把本次只读计划当已完成发包。正式新build-info、说明和current-pointer必须另生成，不能复制旧c9b6d86元数据伪装新包。私有原版资产继续仅本地保存，不推断公开再分发许可。

本机证据：`D:/AgentGamePipeline/evidence/dust-release-audit-20261029/release/delivery-plan.json`。实际44项来源大小/哈希核验成功；自查后补齐新收据必须包含EXE、主PCK和雷达PCK三件的门闸，缺主PCK不会静默沿用旧主包。4项回归覆盖路径逃逸、错误字节身份、已有输出不被覆盖及新收据缺件。Ruff F、格式、Pyright零错误；门闸修复仅做定向检查，未重复5GB哈希。仅作者工具，无GPU或可选环境入口新验收，不重复生产原生套件。

下一步：待材质生产树冻结后统一生成最终标准包，补新主PCK下可选环境入口三图流程，再写新元数据/操作说明，最后原子切换桌面入口。仍需最新完整比赛、连续人工三图与逐图70%FPS，不以普通短时开局替代。
