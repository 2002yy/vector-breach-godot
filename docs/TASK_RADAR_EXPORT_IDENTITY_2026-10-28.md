# R38 雷达导出身份与原字节去重

默认原GLB存在时仍走原SHA256和原.import严格校验；不允许用导出收据绕过已存在但错误的原文件。只有原GLB字节不存在时，允许atlas同目录的export_identity.json提供schema1导出身份。收据绑定source/source_sha256/source_import_sha256/level_sha256、原atlas.json字节哈希、实际随包.import字节哈希、该sidecar声明的.godot/imported/*.scn路径及其SHA256。路径不得含..；必须存在。compiled字节哈希仍由异步worker实算；缺失、陈旧或不匹配均回退，不能只相信complete字段。源工程仍执行原始材质/碰撞导入身份合同。

新增作者构建器tools/authoring/build_radar_export_pack.gd先核对原GLB/原.import/关卡哈希，生成仅含资产的精确PCK：3份收据、3份atlas、3份关卡JSON、3份sidecar、3份实际compiled collision与26PNG；不含产品脚本或原GLB。包必须为新路径，不覆盖现存文件。编译资源是正式产品本来需要保存的一份碰撞资源，未来整合应复用，不能再附加同样的资源。构建器用于建立可审计资源清单，不会自动修改export_presets或桌面启动包。

隔离空项目（产品RadarAtlas脚本独立复制，不放进资产PCK）挂载实际包，三图26切片校验/异步解码通过；验证前原GLB缺失，并断言包内没有原GLB。缺compiled、陈旧compiled digest、缺receipt三份负包全部source_identity_mismatch。正包135,447,680字节，旧原GLB诊断包359,490,460字节；其中compiled资源占主要体积，单独atlas/收据等额外数据约1.65MB。此证明实际pack内的碰撞资源字节身份与雷达对应，不证明所有compiled scene依赖均可实例化，也不是最终EXE验收。

本机证据D:/AgentGamePipeline/evidence/radar-export-identity-20261028/package/：results.json、final-check*.log、focused-final.log、isolated与四个诊断PCK。原生雷达176检查通过，格式和lint零错误。初轮额外字段复制导致原mutable manifest drift测试失效，已恢复原源SHA终态校验；该失败在工具输出中记录，未声称初轮原始log另存。初轮缺receipt使用空JSON产生诊断，现先检查存在；最终负例日志干净。身份setup抽取为独立函数以控制return数量，无全文件lint豁免。

剩余：从真实最终导出PCK生成而非仅本机导入缓存生成收据；实际主包一次包含compiled collision和其全部依赖；正式EXE无本地目录回退三图验证；损坏sidecar/atlas/关卡/receipt的逐项最终包负例；最终包体积/加载预算。收据与atlas同属构建产物一致性合同，不是外部签名信任边界。原版纹理/参数/几何和当前玩家参数均未改。
