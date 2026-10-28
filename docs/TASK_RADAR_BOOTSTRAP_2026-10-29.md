# 导出运行时自动挂载雷达资产附包

基线dea0af0。新增首个autoload `RadarPackBootstrap`，在Main之前的_enter_tree执行。编辑器/源码运行跳过；导出运行时只检查实际可执行文件同目录固定文件名 `VectorBreach-radar.pck`，不扫描任意目录、不读取用户设置。文件不存在返回absent，基本PCK头损坏返回invalid；原雷达缺失回退保持。mount使用 `replace_files=false`，附包无法替换主产品已有脚本、关卡或project配置。

该附包只应包含构建器输出的atlas、PNG与身份收据；bootstrap不替代RadarAtlas的实际来源/compiled collision、atlas、切片哈希校验。原产品已有atlas保留，缺失的原PNG字节与export_identity.json由附包提供。需要重新生成真实导出包才能使autoload成为正式EXE入口；源码Godot引擎带editor feature，因此隔离测试显式调用相同bootstrap函数的受控exported_runtime=true分支，不冒称新EXE已运行。

新作者测试 `tools/authoring/test_radar_bootstrap.gd` 在空项目执行：将生产bootstrap复制为res://RadarPackBootstrap.gd、工具复制为res://test.gd，并创建existing.txt=product；参数是尚不存在的外部新用例目录。实际断言覆盖source跳过、缺片、损坏头、正确挂载、源码即使旁置合法包也不加载、已有product资源不被覆盖、新资产可读。格式/lint通过，focused.log marker `RADAR_BOOTSTRAP_OK source_absent_corrupt_mount_no_override`。

另在空项目挂载R39实际标准产品PCK，并把1,631,716字节资产包以固定文件名放置在夹具可执行路径旁，调用正式bootstrap并保持false覆盖策略；加载产品自己的导出RadarAtlas，三图26切片校验和异步解码通过。结果 `RADAR_FINAL_READY maps=3 slices=26`。此步骤未覆盖产品脚本、重复compiled collision或改变旧试玩包。

本机证据 `D:/AgentGamePipeline/evidence/radar-bootstrap-20261029/bootstrap/`：focused.log、actual-pack.log及隔离脚本。现有缺失资产回退不被当作成功加载；损坏包不应阻塞正常无雷达背景的启动。

随后按授权仅执行一次真实Windows release导出，产物位于同级 `exe-candidate/`，并从这份实际主PCK重建固定命名附包。release模板不支持路径覆盖：`--main-pack`明确报错，`--script`尝试120秒超时，日志保留。改用相同release EXE的字节一致副本与极小诊断主PCK并置，诊断项目包含原生产bootstrap autoload，启动时不注入exported=true；实际OS.editor=false、自动挂载成功，再挂载真实产品PCK，三图26切片全部通过。最终 `diagnostic-normal/stdout-v2.log` 干净，marker为 `RELEASE_BOOTSTRAP_RADAR_OK editor=false automatic=mounted maps=3 slices=26`。初轮诊断包缺global script cache的两条错误单列保留，补齐诊断cache后复验无ERROR。

这是实际release二进制、真实导出PCK和自动分支的证明，但使用诊断主项目而非正常产品Main；正常Main的冻结布局身份问题由独立通道记录，不绕过。真实最终EXE正常开局/布局、坏PCK有效头损坏负例、比赛及帧率继续待验。新导出物并未替换桌面试玩包，不能作为可玩版本放行。
