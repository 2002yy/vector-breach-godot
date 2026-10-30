# R49 实际新包雷达底图可见验收

最终runtime0a2968a，图形验证时candidate位于本机r49-20261031/normal-export/candidate，现已同盘发布到D:/VectorBreach/releases/VectorBreach-playtest-20261031-candidate，位置映射/文件身份/桌面备份见preview-publication.json。实际普通EXE与实际EXE可选环境入口均逐图通过菜单→购买→就绪→战斗；12张有效start/ready图已逐张查看，三图底图均恢复可读建筑边界与区域填色。可选Inferno首次22秒截图仍在加载，保留为早期样本，仅补该入口40秒等待后的购买/战斗两图，不将早图冒充购买通过。输入/截图沿用自有PID/HWND投递和PrintWindow，无全局输入或抢前台。

新增作者工具probe_radar_visible_basemap.gd，继承冻结可选GPU探针，仅在诊断宿主对产品HUD做只读断言和临时采样。实际新PCK/正确附包、全部保留raw GLB共存（隔离host同盘硬链接，没有代码覆盖或重复大资源）。三图Vulkan均退出0、零ERROR，角色/玩家/观战手臂绑定通过，atlas ready，层数8/9/9合26；当前选择层距离脚底采样不超过2.5m，且符合最近层加0.25m滞回合同。这里是三图当前玩家/观战位置的选层验证，并非26个楼层逐层GPU运动验收。

同姿态冻结game，先正常截图，再只将雷达底图纹理替换透明1px，保留网格/标记；恢复后继续退出。内圆80%区域中差分超过8/255的像素比例：Dust玩家/观战68.66%/68.20%，Mirage58.87%/64.79%，Inferno90.40%/89.37%。图已查看，证明底图真实参与画面；不代表几何覆盖率、原引擎等价、定位/朝向全路线正确或70%FPS。诊断冻结/回读使HUD瞬时帧率不适合作性能基准，观战模式文字也可能滞后；内部手臂绑定断言不替代连续观战UI体验。

完整证据：`D:/AgentGamePipeline/evidence/r49-20261031/entry/result.json`、12张选定实图、三图gpu-*的正常/hidden对照、radar-visibility.json与process收据。所有测试进程已退出，未改candidate文件或metadata。原RadarAtlas raw+export双身份改动独立只读审查未发现确定P0/P1：坏receipt不降级、raw/compiled均核验、import变化及旧generation结果拒绝。

旁项：就绪点击后手枪12→11再次出现，可能是输入透传或自动化同帧投递效应；本轮仅记录，不作确定缺陷或扩大生产修改。正式18场、连续人工三图、远层过渡/雷达实战信息和性能仍待验。
