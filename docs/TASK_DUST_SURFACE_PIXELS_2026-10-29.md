# R43 Dust II 点状细面归因

追加原始通道核对：从原GLB的JSON chunk直接提取extras.vmat，链网使用csgo_vertexlitgeneric.vfx、F_ALPHA_TEST=1、g_flAlphaTestReference=0.5、g_flAntiAliasedEdgeStrength=1；glTF为MASK。PNG为512×512 RGBA，Alpha范围0–255，209408/262144个像素Alpha=0。完整参数/纹理SHA/直方图及源小图见chainlink-source.json、chainlink-original.png、chainlink-alpha.png。这里核对的是现有原GLB中保存的VMAT参数，没有声称重新从VPK解码验证。

追加实际运行时读数在alpha-coverage/materials.json：链网仍使用同一路径原PNG，transparency=2、alpha_scissor_threshold=0.5、texture_filter=3，但alpha_antialiasing_mode=0、edge默认约0.3。裁切模式/阈值与原参数相符；原有抗锯齿边缘效果尚未接入，不能据对象定位宣布栅栏渲染完全正确。

按[Godot官方StandardMaterial3D文档](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html#alpha-antialiasing)，alpha AA的edge应低于scissor阈值，推荐至少2×MSAA。故原EdgeStrength=1不能直接填成Godot edge=1。追加仅链网alpha-to-coverage候选，保持原PNG/阈值0.5，分别edge0.25和0.4（项目既有2×MSAA），截图见alpha-coverage/chainlink-alpha-coverage-{quarter,four-tenths}.png；两图均已查看，未消除远距密集网纹，不能凭单距离静帧裁定最优参数。此候选也累计关闭SSAO/SSIL/阴影、near重置0.05；未用于正式材质。后续需要固定多距离/侧视/运动覆盖率与原客户端对照，再决定适配规则。v2/v3各自新目录和日志保留，不覆盖初轮六态证据。

基线19291ac，仅新增作者探针，不修改正式材质、原资源、几何或Current。实际Vulkan Forward+、1280×720、原T出生视角，Godot内部viewport截图复现标准EXE截图中的右侧点状表面，故并非Windows截图独有。证据目录：`D:/AgentGamePipeline/evidence/dust-release-audit-20261029/dust/`。

右门点状表面已定位为`dust_chainlink_fence_wire_001`链网栅栏。仅隐藏使用该材质的可视Mesh时，门洞内密集点状层消失且露出后方空间，见chainlink-hidden.png；恢复后重现。原纹理`assets/local_reference/dustline/dust_chainlink_fence_wire_001_mip0_color_tga_5081421d.png`已查看，内容为菱形金属网。运行时15个相关材质表面使用alpha scissor（枚举2）。该定位不能证明远距采样/抗锯齿已经正确，也不能把“点状墙”直接当作多余面删除。

探针逐步叠加对照如下，非独立单变量全因子试验：

|截图|累积状态|观察|
|---|---|---|
|baseline|产品正常设置|复现右门链网及遮棚细点|
|no-screen-occlusion|关闭SSAO/SSIL|细点仍在|
|no-shadows|以上再关闭所有Light3D阴影|细点仍在|
|near-half-meter|以上再将Camera near改0.5|细点仍在，第一人称手臂被裁，不能作为修复|
|chainlink-hidden|near改0.05；关闭链网可视Mesh|右门点状层消失，遮棚仍在|
|forced-opaque-diagnostic|恢复链网，再将StandardMaterial3D强制不透明|链网后方被灰面遮住，网纹仍在；该设置会破坏其他透明面，不能应用产品|

材质清单materials.json记录3618个StandardMaterial3D表面：不透明3200、alpha scissor329、alpha depth prepass63、alpha26。不是3618个唯一材质。探针的所有关闭/强制不透明设置仅存在于测试进程，未写设置文件。最后一轮Godot退出0、DUST_PIXEL_PROBE_DONE，GDS格式/lint通过。

尚未确认遮棚细点是原纹理细节、重叠面还是采样问题；本轮未实施生产修复。后续应先按视线定位遮棚具体Mesh/材质，再核对原纹理alpha/UV及重复三角证据，随后比较采样策略，避免通过删除原网格或全局关闭透明“修好”截图。三图画质/70%FPS与完整比赛未据此放行。

运行：编辑器版Godot `--path . --rendering-method forward_plus --resolution 1280x720 --position 2000,1200 --script tools/authoring/probe_dust_surface_pixels.gd -- <新证据目录>`。工具拒绝覆盖已有baseline.png；早期作者迭代使用固定目录重拍，保留的是最终同进程六状态对照。最初误用de_dust2 ID导致退出1，后改为真实dustline-depths-original-local；没有把该失败算作渲染失败。
