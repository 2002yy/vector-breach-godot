# R44 Dust II 遮棚物体与原材质核对

基线fdba4e3，只新增独立作者探针`tools/authoring/probe_dust_awning.gd`，不修改原几何、纹理、正式材质、AI或Current。原R43探针保持。两个独立Vulkan Forward+运行均退出0并输出DUST_AWNING_DONE，1280×720产品T出生视角，Godot内部viewport截图；不争抢系统焦点。证据位于`D:/AgentGamePipeline/evidence/c4-recovery-20261029/material/awning-v1/`与`awning-v2/`，相应进程日志在evidence根目录的awning-probe*.log。

首轮三条视线逐可见mesh三角求交，命中的是`hr_dust_plaster_09`后墙，不能把它当遮棚材质。细杆之间的空隙会让稀疏射线穿过；保留ray-hits.json作为未命中目标的证据，未据此改变墙材质。第二轮按原材质名分别隐藏，并在每张截图后恢复：

|仅隐藏的材质|截图观察|
|---|---|
|dust_awning_02|当前右侧目标遮棚未明显消失|
|dust_awning_fabric_01|左侧红布边条消失，骨架保持|
|dust_awning_fabric_frame_01|横跨两个门洞的浅色细金属骨架消失，后方残余布面可见|
|dust_awning_fabric_ripped_01|此出生视角目标未明显消失|

以上四张及baseline均已逐张查看。点状细节所在的浅色骨架因此定位为`dust_awning_fabric_frame_01`，不是R43右门链网材质。隐藏仅为定位对照，不作为游戏修复，也不宣称隐藏整材质能精确分离每个像素的贡献。

从现有原GLB JSON chunk直接提取相关materials/extras.vmat及baseColorTexture，保存在`material/source-awning.json`；未声称重解VPK。骨架原VMAT为`csgo_vertexlitgeneric.vfx`，无F_ALPHA_TEST，glTF未设alphaMode（默认不透明）；原PNG为RGB，无Alpha通道，SHA256为`88b347f9c10891af902c23f5f408c60fc8640ae718c81e69cb98f8fea8a0a5a8`。R43同生产树运行材质清单中该材质transparency=0，与原不透明规则一致。已查看原PNG，其内容自身有锈斑、磨损、孔点/金属连接图案，不能通过给这张RGB纹理补透明或删网格来消除细点。fabric_ripped_01另为RGBA、Alpha0–255，不能将其参数误套到骨架。

本轮排除了“骨架原Alpha丢失”的假设；未证明全部远距点状都来自原美术而非采样。仍需冻结可见骨架特定三角/UV及视距做运动和多距离对比，检查重复共面三角/深度与纹理过滤，不据当前定位宣称整个遮棚已修好。无确定的生产修复依据，正式渲染未变。新GDS格式/lint通过，不触发生产原生全套重跑。

运行需编辑器版Godot：`--path . --rendering-method forward_plus --resolution 1280x720 --position 2000,1200 --script tools/authoring/probe_dust_awning.gd -- <全新输出目录>`。工具拒绝复用已存在目录；原纹理/GLB不写入。摄像机坐标与射线选择随截图冻结，不能将稀疏射线漏中当作网格不存在。
