# R51：C4归属、UI输入与雷达修复

基线586b052a729f80498254c169af0fd5ed60e41a09，分支fix/objective-owner-lifetime；PR基于test/frozen-match-matrix（#147），不等待CI，不合并。提交/PR与精确头CI首次查询记录在外部delivery.json。本批跨2026-10-31/11-01，证据目录保持r51-20261031。

## 行为与边界

- RoundManager将真实交互绑定actor和C4弱引用。死亡/释放/掉弹/回合结束清理；接替重新按本人的拆弹器计5/10秒，旧owner不能影响新owner。纯管理器测试原无actor API继续支持，真实Main/Brain调用均绑定。
- Main仅限制本地自己的交互；AI安装/拆弹期间本地仍可掩护。AI取消只释放自己的占用，死亡/停用/撤退/换弹分支不留本地标志。
- 购买/菜单/帮助切换同步撤销输入许可；开放战斗后先观察全部相关键释放，整个过渡帧仍屏蔽新射击/开镜/交互。移动不等待该门闸，已有暂停交互不因门闸无故清除。
- RadarObservationMemory仅在合法可见时更新敌位置与朝向；失视野显示最后观察而非真实实时坐标，2.5秒TTL到期清除。观战统一用有效同队角色姿态，切人只重置楼层样本。地图旋转与角色朝向分开，北向及队友箭头符号匹配Godot 3D forward。

不调整Current移动数值、枪械经济、地图布局/碰撞/导航或原版资产。不扩大本批为闪光/C4情报公平性策略重做。

## 本地证据

证据根D:/AgentGamePipeline/evidence/r51-20261031/：

- owner-red.log：真实伤害链在旧实现8断言失败；owner-final.log及native-final-TacticalBombTestRunner.log：新实现定向及29项套件通过，覆盖死亡、自由接替、kit、暂停、掉弹、回合结束、释放及旧owner隔离。
- main-owner-red.log与main-owner-final.log：真实Main掩护移动/武器/开火旧红新绿。早期物理协程注入开火未形成process边沿，只修测试时间线。
- native-suite.log：完整16套件运行到Main52项，仅旧C4提示测试失败；新输入门闸要求UI关闭后经过松键帧，该测试此前直接手动调用交互。只补测试准备和定向入口，c4-prompts-final.log通过；保留原失败，不重复已绿全套，续跑剩余六套件，组合覆盖见native-acceptance.json/log。不得将组合成功伪称原标准脚本一次性RUN_ALL_OK。
- radar-red.log、radar-final.log：真实墙体遮挡、隐藏敌移动与朝向冻结、TTL、观战中心/脚底/切换及数学回归。初期编译错误留证，最终扫描ERROR独立于退出码。
- python-full.log：629项通过。lint-delta.json：相对基线按文件+函数+消息逐项比对，无新lint债务；新文件格式通过，diff --check通过，GDS静态解析由原生运行覆盖。
- radar-heading-before/after.png与radar-gpu.json：实际RadarDisplay组件Vulkan八方向截图，已目视PASS；隐藏不激活自有父窗口，不向用户窗口发输入。该图不是三图场景、普通EXE、连续观战或FPS证据。源码格式整理不改变该渲染函数行为。

## 未放行与下一片

R50的18场/182回合是修复前基线，原5个安装owner残留候选及Mirage时限/回收风险需按新生产树重验。当前预览runtime0a2968a未重导，不含本批修复。连续人工三图、M4/M5、AI难度、角色原引擎效果及逐图70%FPS仍待完成。下一片先新源比赛/风险窗口，再连续UI/观战/楼层与受影响试玩包验收。四份既有脏导入和用户设置须保持。
