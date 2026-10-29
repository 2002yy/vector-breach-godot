# R44 可选环境入口：实际标准包兼容性预检

基线fdba4e3，标准包仍为R42未变生产树的导出，不含R44的AI修复。只新增作者预检，不复制大包、不改桌面入口、不改生产环境配置。旧支持文件来源由R43交付计划逐文件SHA绑定。

实际`standard-release-20261029/candidate/VectorBreach.exe`以`--headless --quit-after 30 -- --controlled-game`及三次绝对`--character-bundle`启动，分别引用现有桌面包candidate-inputs/{dust2,mirage,inferno}/bundle.json。进程正常退出0，日志无ERROR，设置SHA前后相同5240ec0a…061b8。这只证明release二进制可接受该启动入口并完成短时菜单启动，不证明三图选择、GPU上传、角色/玩家及观战手臂效果已生效。

新增`tools/authoring/check_optional_release_inputs.gd`在空项目挂实际主PCK与统一附包，动态加载产品内LaunchRouter和SourceCharacterRuntimeInputs，不加载当前工程脚本来代替产品代码。确认controlled-game路由，再对旧三图bundle调用导出产品的inspect：来源level/vpk、声明大小/SHA、五类输入及间接依赖均通过。三图实际各返回reflection/lighting/normalization/indirect/alignment五项，EXPORTED_OPTIONAL_INPUTS_OK，退出0。主PCK SHA为70bf75e4…cbec5，附包0009a6e0…f9b60e，完整值在inputs.json。

首次隔离尝试加载ControlledGame的静态catalog，间接编译Main时缺少空项目未配置的GameState等autoload而失败；这是作者隔离方式错误，不是产品启动失败。原日志inputs-initial.log保留。最终探针只检查不依赖Main的产品输入合同，不声称已执行ControlledGame.bundle_catalog或实例化角色场景。实际EXE短启动作为独立证据。

证据目录`D:/AgentGamePipeline/evidence/c4-recovery-20261029/release/`：inputs.json/inputs.log、actual-exe.log、result.json，外部run.py保留参数与设置哈希。GDS格式/lint通过；无生产变更，本通道不重复原生全套。

下一门闸：R44生产树冻结并重新标准导出后，使用同一主PCK与三图旧输入，在Vulkan下实际走可选入口三图开始→输入上传→角色/玩家手臂→死亡观战手臂并查看截图。当前仅headless/CPU合同预检，gpu_configure_verified=false；不能拿它替代可选环境入口画质验收或激活桌面新版。主包与支持文件仍保留，未删除任何旧载荷。

复用：用编辑器版Godot在空项目执行此脚本，`-- <实际主PCK> <匹配雷达附包> <旧支持根目录> <不存在的输出JSON>`。输出文件存在即拒绝；输入应先经交付计划核对来源哈希。
