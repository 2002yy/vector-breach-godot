# R45 实际标准包可选环境三图Vulkan兼容性

起点85cc0f3，跨日至2026-10-30收尾。使用R42实际主PCK与匹配雷达附包，在独立编辑器Vulkan诊断宿主中先挂包，再加载产品ControlledGame和产品autoload；三图bundle引用旧试玩包的绝对路径。产品代码均来自该实际包，无代码覆盖层。此为旧包兼容性，不是普通release EXE操作验收，也不含R44/R45的新AI代码；没有复制新3.6GB主包或切换桌面入口。

第一次只挂标准三件包并提供bundle时，Dust配置被拒绝。最终诊断确认：CPU输入合同有效、visual/runtime同viewport，但SourceVisualAlignment要求的原视觉GLB不存在于标准PCK，原SHA为空，解析determinant为0。不是GPU上传已发生后失败。旧完整交付清单本来就保留`assets/local_reference/dustline/de_dust2_original.glb`（313,042,936字节、SHA6e84e198…3e4b），初版诊断遗漏了这项载荷；不得据此说完整旧配套必定不可用或放松对齐校验。

将该旧文件按build-info和alignment两处原SHA核对后，制作仅含原数据的临时诊断附包，replace_files=false，无脚本和原几何修改。补齐这项已有配套载荷后，Dust、Mirage、Inferno各独立Vulkan进程均退出0，runtime配置及角色绑定有效，玩家手臂和实际死亡后第一人称观战手臂均被绑定，六张最终截图逐张查看。三图均输出OPTIONAL_EXPORT_VULKAN_READY。该补包是读取完整交付所需原字节的诊断方式，不能当作R45新产品补丁直接发布。

结果在`D:/AgentGamePipeline/evidence/c4-approach-20261029/optional/{gpu-with-support,gpu-mirage,gpu-inferno}/result.json`及PNG。诊断实测子viewport为1600×900、MSAA0，root为MSAA1；不能把root的2×MSAA当作子viewport配置。此通道只确认输入/绑定/截图可用，未通过原引擎等价、材质观感、抗闪烁或70%FPS验收。瞬时HUD帧率受初始化与候选负载影响，不能充当固定基准。初版断言失败后继续AI导致的Nil调用错误保留，最终有界失败和成功日志均无SCRIPT ERROR/ERROR。

新增`tools/authoring/probe_optional_export_vulkan.gd`为诊断工具，四个首参数为实际主PCK、雷达PCK、全新输出目录、可选数据附包（或reserved），其后传三次--character-bundle，可用--probe-map选择地图。工具挂载实际产品代码，拒绝覆盖输出；图形窗口放在屏幕外，使用viewport内部截图，不抢用户焦点。CPU合同预检与本图形验证边界见上批TASK_OPTIONAL_RELEASE_ENTRY。

下一步把本轮生产树一次标准导出，与完整载荷和新元数据组合后，再走普通EXE双入口与三图流程；完整角色/第一人称/观战材质质量、连续切人/重建与性能仍待验。原视觉字节若要从交付包省去，必须另建绑定实际编译资源的等强身份合同，不能直接删除。

三个GPU进程结束后，临时桥接PCK313,043,172字节已按support-pack-receipt SHA及三图成功收据删除，原313,042,936字节视觉GLB保留；日志、截图和可重建脚本仍在optional目录，bridge-cleanup.json记删除动作。桥接包历史路径不再存在，不代表原配套载荷可删。
