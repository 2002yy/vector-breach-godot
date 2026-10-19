extends RefCounted

const CONTROLS := "WASD 移动 · 鼠标瞄准 / 左键射击\n狙击枪：右键开关瞄准镜，射击后退镜\n持刀：左键挥砍 / 右键重刺；背后命中 3 倍伤害 · 手雷：左键投掷\nShift 静步 · Ctrl 蹲伏 · 空格跳跃\n1 主武器 · 2 手枪 · 3 刀 · 4 切换投掷物 · 5 C4（持有时）\nR 换弹 · G 丢弃 · E 拾取 / 按住安装或拆弹\nB 购买（出生区准备阶段）· Tab 计分板\n死亡观战：左键 / 滚轮下 下一位；右键 / 滚轮上 上一位\n空格切换队友眼位 / 第三人称；没有存活队友时等待回合结束\nEsc 暂停菜单 · F11 全屏 · F1 操作帮助"
const MATCH_RULES := "门厅区：你 + 两名队友，对抗三名敌人。\n首局 / 换边后：双方均为手枪 + $800。\n步枪 $2700，攒钱后在准备阶段按 B 购买。\n准备最多 60 秒，购买页点就绪即可开战。\n进攻方带炸弹前往 A / B 区，按住 E 安装；\n防守方阻止安装，或到炸弹旁按住 E 拆除。"
const PRACTICE_RULES := "独立训练场：无限备弹、自动补雷、靶子重生。\nF2 轮换步枪 / 狙击枪 / 冲锋枪 / 霰弹枪。\nF5 重置 · F6 补给清场 · F7 返回选图 · F4 统计。\n练习地图开局配有步枪和手枪，按 1 / 2 切换。\n铸造厂·重构用于练习与画面展示，\n其余历史 / 测试地图不代表完整平衡比赛。"
const RESEARCH_RULES := "经典地图：你 + 四名队友，对五名敌人。\n首局 / 换边后：手枪 + $800；步枪 $2700。\n准备最多 60 秒，购买页点就绪即可开战。\n进攻方前往 A / B 爆点，按住 E 安装；\n防守方阻止安装，或到炸弹旁按住 E 拆除。\n参考地图资源仅保留本机。"


static func weapon_name(weapon_id: String) -> String:
	return String(
		(
			{
				"rifle": "步枪",
				"sniper": "狙击枪",
				"smg": "冲锋枪",
				"shotgun": "霰弹枪",
				"fire_grenade": "燃烧弹",
				"pistol": "手枪",
				"knife": "战术刀",
				"he_grenade": "高爆手雷",
				"flash_grenade": "闪光弹",
				"smoke_grenade": "烟雾弹"
			}
			. get(weapon_id, weapon_id)
		)
	)
