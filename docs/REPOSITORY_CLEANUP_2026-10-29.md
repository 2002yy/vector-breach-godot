# 仓库与旧导出清理

按用户要求暂停开发，先盘点仓库和同项目证据目录，再清理已被替代的可重建导出文件。

盘点：仓库约10.19GiB，其中`.godot/imported`约5.34GiB、原版`assets/local_reference`约4.59GiB；证据目录约40.12GiB。仓库Git对象约0.07GiB，不是本轮空间增长的主要来源。活动导入缓存与原资产保留。

删除9个旧PCK，共10,927,495,999字节（10.177GiB）：

- `official-character-equipment-20261017`：两个before-fix回退导出包。
- `radar-final-pack-20261029/package/product.pck`：已被R40标准release基线替代。
- `radar-player-package-20261028/package`：旧原GLB正包与缺片负包。
- `radar-export-identity-20261028/package`：旧compiled身份正包与三份负包。

这些旧产物的日志、截图、JSON、构建工具与删除前SHA256仍保留；历史文档中的相应PCK路径现在可能不存在，需按原命令重建，不能误报它们仍在本机。没有删除原始光照采样、原纹理/着色器、视频、源码、工作树、模型或当前试玩包。

删除采用显式清单，逐文件检查允许根路径、非reparse目标、长度与SHA256，再执行非递归删除；动作收据区分deleted与already_absent，本次9项均deleted。实际D盘可用从约2.89GiB增加到12.84GiB，不能将并发磁盘活动下的净变化与逻辑删除量混同。

保护核验：85份旧工具、四份既有脏导入、用户设置和桌面试玩包通过原保护脚本；R40最新标准基线的EXE/PCK/雷达附包逐项SHA256保持。当前运行时HEAD仍为R41的`5b6c1e0`；本次仅更新文档，不重复游戏全套。

本机收据：`D:/AgentGamePipeline/evidence/cleanup-20261029/`，包括`inventory.json`、`cleanup-plan.json`、`cleanup-actions.json`、`cleanup-result.json`、`final-verification.json`。未清理其它项目或D盘其它数据。

下一批继续R41后的最终标准导出/三图图形开局，以及保留原三角集合的碰撞分块独立实验。清理不代表候选已合并或试玩包已更新。
# 新标准EXE开局补验后的追加清理

R42标准候选已完成正常菜单三图开始、购买、就绪和战斗截图检查。随后仅删除被替代的R40 `radar-bootstrap-20261029/exe-candidate/VectorBreach.pck`，3,620,457,009字节（约3.37GiB）；删除前核对旧哈希24daf505…abff94与新包70bf75e4…cbec5，保留新标准包、全部日志/收据、原版资产及现有桌面试玩包。此项追加在前述9文件清理之后，总计10个旧PCK、逻辑14,547,953,008字节。收据：`D:/AgentGamePipeline/evidence/standard-release-20261029/superseded-cleanup.json`。历史保留清单中的R40主PCK从此不再存在；诊断日志和身份结果仍保留。实际释放量与逻辑字节数不混算。
