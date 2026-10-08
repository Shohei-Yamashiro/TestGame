extends RefCounted

# --- Player ---
const PLAYER_MAX_HP := 100
const HURT_INTERVAL := 0.4
const CONTACT_STACK := 3
const BULLET_SPEED := 560.0
const BASE_MAGNET := 140.0

# --- Round: fixed length, scored ---
const TIME_LIMIT := 180.0
const LAST_SPURT := 30.0
const LAST_SPURT_SPAWN := 0.65
const CLEAR_BONUS := 3000
const HP_BONUS_PER_POINT := 20
# Level-ups after everything is maxed: heal if hurt, otherwise this many points.
const OVERFLOW_SCORE := 500

# --- Slots and stages: owning an item starts it at Lv1; weapons go to Lv5 then a Lv6 special, passives stop at Lv5 ---
const MAX_WEAPONS := 4
const MAX_PASSIVES := 4
const MAX_STAGE := 5
const SPECIAL_STAGE := 6
const HEAL_AMOUNT := 35
# Small repair kits dropped by enemies: the chance per kill grows with the enemy's XP. Like gems they stay until taken,
# with a cap so they never litter the arena.
const HEAL_DROP_PER_XP := 0.01
const HEAL_MAX_ON_FIELD := 30
const HEAL_PICKUP := 8
# Points for a kit picked up at full HP.
const HEAL_SCORE := 50

# "stats" entries are [key, level-up text, short label for the library table].

# --- Passives: arrays are indexed by stage, so index 0 is the value before the passive is taken ---
const PASSIVE_ORDER := ["attack", "rate", "move", "magnet", "max_hp", "regen", "area", "armor", "growth", "knock"]
const PASSIVES := {
	"attack": {
		"name": "攻撃力",
		"damage": [1.0, 1.18, 1.36, 1.55, 1.75, 2.0],
		"stats": [["damage", "全武器のダメージが増加", "ダメージ倍率"]],
	},
	"rate": {
		"name": "攻撃速度",
		"cooldown": [1.0, 0.9, 0.82, 0.75, 0.68, 0.62],
		"stats": [["cooldown", "全武器の攻撃間隔が短縮", "攻撃間隔倍率"]],
	},
	"move": {
		"name": "移動速度",
		"speed": [230.0, 245.0, 260.0, 275.0, 290.0, 310.0],
		"stats": [["speed", "移動速度が増加", "移動速度"]],
	},
	"magnet": {
		"name": "回収範囲",
		"magnet": [BASE_MAGNET, 185.0, 230.0, 280.0, 340.0, 420.0],
		"stats": [["magnet", "経験値と回復アイテムを引き寄せる範囲が拡大", "回収半径"]],
	},
	"max_hp": {
		"name": "最大HP",
		"max_hp": [PLAYER_MAX_HP, 115, 130, 150, 170, 200],
		"stats": [["max_hp", "最大HPが増加（増えた分だけ回復）", "最大HP"]],
	},
	"regen": {
		"name": "再生",
		# HP per second.
		"regen": [0.0, 0.4, 0.7, 1.0, 1.4, 1.8],
		"stats": [["regen", "HPが少しずつ回復", "毎秒回復量"]],
	},
	"area": {
		"name": "効果範囲",
		"area": [1.0, 1.15, 1.3, 1.45, 1.6, 1.8],
		"stats": [["area", "爆発・波・刃などの範囲とレーザーの太さが拡大", "範囲倍率"]],
	},
	"armor": {
		"name": "装甲",
		# Fraction of incoming damage removed.
		"armor": [0.0, 0.1, 0.18, 0.26, 0.33, 0.4],
		"stats": [["armor", "受けるダメージを軽減", "軽減率"]],
	},
	"growth": {
		"name": "成長",
		"xp": [1.0, 1.12, 1.25, 1.4, 1.55, 1.7],
		"stats": [["xp", "獲得経験値が増加", "経験値倍率"]],
	},
	"knock": {
		"name": "衝撃",
		"knock": [1.0, 1.4, 1.8, 2.2, 2.6, 3.0],
		"stats": [["knock", "ノックバックが強くなる", "ノックバック倍率"]],
	},
}
const BLASTER_SPECIAL_PIERCE := 3
# Weapons get a noticeable boost here, a step on the way to the special.
const MILESTONE_STAGE := 3

# --- Weapons: each stat array is indexed by level - 1 (Lv1..Lv5); the special keeps Lv5 stats ---
const STARTING_WEAPON := "blaster"
const WEAPON_ORDER := ["blaster", "homing", "orbit", "nova", "laser", "wings", "chain", "tesseract", "mine", "drain"]
const WEAPONS := {
	"blaster": {
		"name": "ブラスター",
		"desc": "一番近い敵へ弾を連射する",
		"damage": [10, 13, 16, 20, 25],
		"interval": [0.30, 0.27, 0.24, 0.21, 0.18],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "マルチロック",
		"milestone_desc": "近い敵を2体まで同時に狙って撃つ",
		"special": "3連ロック・貫通弾",
		"special_desc": "近い敵を3体まで同時に狙い、弾が敵を3体まで貫通する",
	},
	"homing": {
		"name": "誘導弾",
		"desc": "近くの敵へ曲がりながら飛ぶミサイルを撃つ",
		"damage": [6, 8, 9, 11, 13],
		"count": [3, 3, 4, 4, 5],
		"interval": [1.4, 1.3, 1.2, 1.1, 1.0],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["count", "発射数が増加", "発射数"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "貫通ミサイル",
		"milestone_desc": "ミサイルが敵を2体まで貫通する",
		"special": "爆裂弾",
		"special_desc": "発射数+1。命中時に爆発し、周囲の敵も巻き込む",
	},
	"orbit": {
		"name": "周回シールド",
		"desc": "自機の周りを回る刃が触れた敵を切り、敵の弾を消す",
		"damage": [7, 9, 11, 13, 16],
		"count": [2, 2, 3, 3, 4],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["count", "刃の数が増加", "刃の数"]],
		"milestone": "大型ブレード",
		"milestone_desc": "刃が大きくなり、当たる範囲が広がる",
		"special": "拡大リング",
		"special_desc": "刃+1。回転半径と速度が上がり、敵の弾を跳ね返して攻撃に変える",
	},
	"nova": {
		"name": "衝撃波",
		"desc": "定期的に自機から広がる波で周囲を攻撃する",
		"damage": [8, 10, 13, 16, 20],
		"radius": [110.0, 120.0, 135.0, 150.0, 165.0],
		"interval": [3.2, 3.0, 2.8, 2.6, 2.4],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["radius", "範囲が拡大", "半径"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "減速波",
		"milestone_desc": "波に当たった敵の移動速度を一定時間下げる",
		"special": "電磁シールド",
		"special_desc": "電気が走るシールドを常に展開し、内側の敵を削りながら減速させ続ける",
	},
	"wings": {
		"name": "光の翼",
		"desc": "背後へ光の翼を広げ、後ろの敵を切り払う",
		"damage": [16, 21, 27, 34, 42],
		"reach": [130.0, 145.0, 160.0, 175.0, 190.0],
		"interval": [2.0, 1.85, 1.7, 1.55, 1.4],
		"feathers": [2, 2, 3, 3, 4],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["reach", "範囲が拡大", "射程"], ["interval", "攻撃間隔が短縮", "攻撃間隔"], ["feathers", "羽根が増える", "羽根の数"]],
		"milestone": "前方なぎ払い",
		"milestone_desc": "羽ばたきの後、翼を振り抜いて前方もなぎ払う",
		"special": "常時展開",
		"special_desc": "光の翼を広げ続けて背後を削り、一定間隔で前方もなぎ払う",
	},
	"laser": {
		"name": "レーザー",
		"desc": "近い敵の方向へ、一直線に貫くビームを放つ",
		"damage": [20, 26, 33, 41, 50],
		"width": [12.0, 13.0, 15.0, 16.0, 18.0],
		"interval": [2.0, 1.8, 1.6, 1.45, 1.3],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["width", "ビームが太くなる", "太さ"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "前後レーザー",
		"milestone_desc": "前と後ろの2方向に同時に照射する",
		"special": "十字レーザー",
		"special_desc": "4方向に同時に照射する",
	},
	"chain": {
		"name": "連鎖電撃",
		"desc": "近くの敵に雷を落とし、そこから近い敵へ次々と連鎖させる",
		"damage": [12, 15, 19, 24, 30],
		"jumps": [3, 3, 4, 4, 5],
		"interval": [1.6, 1.5, 1.4, 1.3, 1.2],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["jumps", "連鎖する数が増加", "連鎖数"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "連鎖強化",
		"milestone_desc": "連鎖する数が2増える",
		"special": "放電",
		"special_desc": "連鎖した敵の周りにも放電し、近くの敵を巻き込む",
	},
	"tesseract": {
		"name": "テセラクト",
		"desc": "進行方向へ4次元立方体を放つ。止まるまでは敵を押し出して削り、止まった後は敵と敵弾を通さない壁になる",
		"damage": [10, 13, 16, 20, 25],
		"life": [3.0, 3.5, 4.0, 4.5, 5.0],
		"interval": [2.4, 2.2, 2.0, 1.8, 1.6],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["life", "持続時間が伸びる", "持続時間"], ["interval", "発射間隔が短縮", "発射間隔"]],
		"milestone": "二重展開",
		"milestone_desc": "鋭角のV字状に2個同時に放つ",
		"special": "共鳴",
		"special_desc": "止まった後も、触れた敵にダメージを与え続ける",
	},
	"mine": {
		"name": "設置機雷",
		"desc": "移動した跡に機雷を置く。敵が触れると爆発し、周囲を巻き込む",
		"damage": [18, 23, 29, 36, 44],
		"radius": [70.0, 75.0, 80.0, 88.0, 96.0],
		"interval": [1.2, 1.1, 1.0, 0.9, 0.8],
		"max": [5, 6, 7, 8, 10],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["radius", "爆発範囲が拡大", "爆発半径"], ["interval", "設置間隔が短縮", "設置間隔"],
			["max", "設置上限が増加", "設置上限"]],
		"milestone": "炎上",
		"milestone_desc": "爆発に巻き込んだ敵が数秒間燃え、継続ダメージを受ける",
		"special": "延焼",
		"special_desc": "燃えている敵が倒れると、周りの敵に火が燃え移る",
	},
	"drain": {
		"name": "ドレインリンク",
		"desc": "HPを消費して最寄りの敵と光の線でつなぎ、削り続ける。与えたダメージの一部と撃破でHPを回復する",
		"damage": [4, 5, 7, 9, 12],
		"drain": [0.2, 0.25, 0.3, 0.35, 0.4],
		"interval": [1.8, 1.7, 1.6, 1.5, 1.4],
		"stats": [["damage", "ダメージが増加", "ダメージ"], ["drain", "吸収率が上昇", "吸収率"], ["interval", "攻撃間隔が短縮", "攻撃間隔"]],
		"milestone": "二重リンク",
		"milestone_desc": "最寄りの2体と同時につなぐ",
		"special": "連鎖吸収",
		"special_desc": "つないだ敵を倒すと、近くの敵へ線が自動で移る",
	},
}
const CHAIN_RANGE := 380.0
const CHAIN_JUMP := 160.0
const CHAIN_FALLOFF := 0.9
const CHAIN_MILESTONE_JUMPS := 2
const CHAIN_DISCHARGE_RADIUS := 60.0
const CHAIN_DISCHARGE_RATIO := 0.5
const CHAIN_SHOW := 0.25
const TESSERACT_MAX := 6
const TESSERACT_RADIUS := 26.0
const TESSERACT_RANGE := 200.0
const TESSERACT_SLIDE_TIME := 0.6
const TESSERACT_TRIGGER := 320.0
const TESSERACT_SPREAD := 0.25
const TESSERACT_HIT_TICK := 0.25
const TESSERACT_REST_TICK := 0.4
const TESSERACT_REST_RATIO := 0.5
const MINE_LIFETIME := 8.0
const MINE_ARM_TIME := 0.3
const MINE_TRIGGER := 24.0
const MINE_SPACING := 36.0
const MINE_BURN_TIME := 3.0
const MINE_BURN_TICK := 0.5
const MINE_BURN_RATIO := 0.12
const MINE_SPREAD_RADIUS := 90.0
const MINE_SPREAD_COUNT := 3
const DRAIN_COST := 3
const DRAIN_MIN_HP := 20
const DRAIN_RANGE := 260.0
const DRAIN_BREAK := 340.0
const DRAIN_TIME := 1.5
const DRAIN_TICK := 0.2
const DRAIN_KILL_HEAL := 3.0
const DRAIN_JUMP := 180.0
const MISSILE_SPEED := 380.0
const MISSILE_TURN := 7.5
const MISSILE_TURN_START := 1.6
const HOMING_RANGE := 460.0
const HOMING_BURST_GAP := 0.06
const MISSILE_BLAST_RADIUS := 64.0
const MISSILE_BLAST_RATIO := 0.6
const ORBIT_RADIUS := 78.0
const ORBIT_SPEED := 3.2
const ORBIT_SPECIAL_RADIUS := 112.0
const ORBIT_SPECIAL_SPEED := 4.2
const ORBIT_HIT_COOLDOWN := 0.5
const NOVA_EXPAND := 0.35
# Shared by the always-on specials (ring of light, deployed wings).
const AURA_TICK := 0.25
const AURA_DAMAGE_RATIO := 0.35
const AURA_KNOCKBACK := 3.0
const RING_RADIUS := 165.0
const WINGS_SPECIAL_REACH := 215.0
const WINGS_SPECIAL_TICK := 0.2
const WINGS_SPECIAL_RATIO := 0.5
const WINGS_CONE := 1.25
const WINGS_SWEEP_RATIO := 1.2
const WINGS_SWEEP_REACH := 1.1
const WINGS_CROSS_RATIO := 0.6
const ORBIT_MILESTONE_SCALE := 1.3
const ECHO_DELAY := 0.25
const NOVA_SLOW_FACTOR := 0.5
const NOVA_SLOW_TIME := 2.0
const BLASTER_MULTI_RATIO := 0.75
const REFLECT_SPEED := 1.8
const REFLECT_DAMAGE_RATIO := 2.0
# --- Library: which passive scales each weapon number ---
# Per-level stats boosted by a passive (the rest, like counts, are untouched by passives).
const STAT_PASSIVES := {"damage": "attack", "interval": "rate", "radius": "area", "reach": "area", "width": "area"}
# Level stats that change on reaching the special (Lv6): "+N" adds to the Lv5 value, a name reads a constant here.
const WEAPON_LV6 := {
	"homing": {"count": "+1"},
	"orbit": {"count": "+1"},
	"wings": {"reach": "WINGS_SPECIAL_REACH", "feathers": 4},
}
# Fixed numbers outside the level arrays that a passive still scales, shown as extra table rows:
# [passive, label, Lv1-5 value, Lv6 value, format]. Strings name a constant in this file, "" means "not used
# at that stage" and null on Lv6 means "same as before". Knockback uses the weapon's own push.
# Keep in step with each weapon's area_of / cooldown_of / cooldown_mult / take_damage calls.
const WEAPON_EXTRAS := {
	"blaster": [["knock", "ノックバック", KNOCKBACK, null, ""]],
	"homing": [["area", "爆発半径", "", "MISSILE_BLAST_RADIUS", ""], ["knock", "ノックバック", KNOCKBACK, null, ""]],
	"orbit": [["rate", "ヒット間隔", "ORBIT_HIT_COOLDOWN", null, ""], ["rate", "回転数（周/秒）", "ORBIT_SPEED", "ORBIT_SPECIAL_SPEED", "turns"],
		["area", "回転半径", "ORBIT_RADIUS", "ORBIT_SPECIAL_RADIUS", ""], ["knock", "ノックバック", KNOCKBACK, 26.0, ""]],
	"nova": [["area", "シールド半径", "", "RING_RADIUS", ""], ["rate", "シールド間隔", "", "AURA_TICK", ""], ["knock", "ノックバック", 14.0, null, ""]],
	"laser": [["knock", "ノックバック", 6.0, null, ""]],
	"wings": [["rate", "常時展開の間隔", "", "WINGS_SPECIAL_TICK", ""], ["knock", "ノックバック", 18.0, null, ""]],
	"chain": [["area", "連鎖距離", "CHAIN_JUMP", null, ""], ["area", "放電半径", "", "CHAIN_DISCHARGE_RADIUS", ""], ["knock", "ノックバック", 4.0, null, ""]],
	"tesseract": [["area", "大きさ", "TESSERACT_RADIUS", null, ""], ["area", "飛距離", "TESSERACT_RANGE", null, ""], ["knock", "ノックバック", 6.0, null, ""]],
	"mine": [["area", "感知半径", "MINE_TRIGGER", null, ""], ["area", "延焼半径", "", "MINE_SPREAD_RADIUS", ""], ["knock", "ノックバック", 12.0, null, ""]],
	"drain": [["area", "つなぐ距離", "DRAIN_RANGE", null, ""], ["area", "切れる距離", "DRAIN_BREAK", null, ""], ["area", "線が移る距離", "", "DRAIN_JUMP", ""]],
}# Knockback reads as a grade rather than a raw push distance.
const KNOCK_GRADES := [[8.0, "弱"], [16.0, "中"], [INF, "強"]]

# Gems: value thresholds for each look, and how close idle gems must be to fuse.
const GEM_TIERS := [1, 3, 8, 20]
const GEM_MERGE_CELL := 40.0
const GEM_MERGE_CELL_CROWDED := 80.0
const GEM_CROWDED := 120
const GEM_MERGE_INTERVAL := 0.4
const LASER_LENGTH := 720.0
const LASER_SHOW := 0.32

# --- Experience ---
const XP_FIRST := 5
const XP_STEP := 3
const XP_CURVE := 0.12

# --- Enemies: kind -> stats. Weak triangles dominate early, tougher shapes join later ---
const ENEMY_KINDS := {
	# Fast, fragile swarm.
	"tri": {"sides": 3, "radius": 10.0, "hp": 0.6, "speed": 1.1, "damage": 2, "xp": 1, "score": 10, "color": 0},
	# The all-rounder.
	"penta": {"sides": 5, "radius": 14.0, "hp": 2.6, "speed": 0.82, "damage": 8, "xp": 3, "score": 40, "color": 1},
	# Tough and slow; barely flinches.
	"hepta": {"sides": 7, "radius": 19.0, "hp": 9.0, "speed": 0.55, "damage": 14, "xp": 7, "score": 120, "color": 2,
		"knock": 0.35},
	# Three-spiked stars: stop, telegraph, then charge in a straight line. Small and twitchy, standard, and a heavy lancer.
	"dart": {"sides": 3, "spiky": true, "radius": 11.0, "hp": 1.0, "speed": 0.95, "damage": 6, "xp": 2, "score": 35,
		"color": 3, "behavior": "dash", "dash_trigger": 220.0, "dash_windup": 0.4, "dash_speed": 720.0, "dash_overshoot": 140.0,
		"dash_cooldown": 1.6, "dash_lane": 1.4},
	"dasher": {"sides": 3, "spiky": true, "radius": 16.0, "hp": 2.0, "speed": 0.75, "damage": 10, "xp": 3, "score": 60,
		"color": 3, "behavior": "dash"},
	"lancer": {"sides": 3, "spiky": true, "radius": 23.0, "hp": 7.0, "speed": 0.6, "damage": 18, "xp": 8, "score": 150,
		"color": 5, "behavior": "dash", "knock": 0.4, "dash_trigger": 380.0, "dash_windup": 0.85, "dash_speed": 980.0,
		"dash_overshoot": 340.0, "dash_cooldown": 3.0, "dash_lane": 2.0},
	# Five- and seven-spiked stars: crawl and fire slow shots. A light turret, the standard one, and a battery firing a fan of three.
	"turret": {"sides": 5, "spiky": true, "radius": 12.0, "hp": 2.0, "speed": 0.5, "damage": 4, "xp": 3, "score": 45,
		"color": 4, "behavior": "shoot", "knock": 0.8, "shot_interval": 3.6, "shot_damage": 5},
	"shooter": {"sides": 5, "spiky": true, "radius": 16.0, "hp": 4.0, "speed": 0.4, "damage": 6, "xp": 5, "score": 80,
		"color": 4, "behavior": "shoot", "knock": 0.6},
	"battery": {"sides": 7, "spiky": true, "radius": 22.0, "hp": 10.0, "speed": 0.32, "damage": 10, "xp": 9, "score": 170,
		"color": 6, "behavior": "shoot", "knock": 0.3, "shot_interval": 3.4, "shot_damage": 8, "shot_count": 3},
}
const DASH_TRIGGER := 280.0
const DASH_WINDUP := 0.55
# The charge runs past the player's (slightly led) position, so backing off is not enough.
const DASH_SPEED := 820.0
const DASH_OVERSHOOT := 220.0
const DASH_LEAD := 0.35
const DASH_LANE_WIDTH := 1.6
const DASH_COOLDOWN := 2.2
const SHOT_RANGE := 520.0
const SHOT_INTERVAL := 3.0
const SHOT_WINDUP := 0.45
const SHOT_SPEED := 190.0
const SHOT_DAMAGE := 7
const SHOT_LIFETIME := 4.0
const SHOT_FAN := 0.32
const SHOOTER_MAX := 14
# Some chasers swing wide while still far off, so the horde fans out instead of trailing behind as one blob.
const FLANK_CHANCE := 0.6
const FLANK_ANGLE := 0.75
const FLANK_NEAR := 140.0
const FLANK_FAR := 360.0
const ENEMY_BASE_HP := 10.0
const ENEMY_HP_GRACE := 30.0
const ENEMY_HP_RAMP := 50.0
const ENEMY_HP_LATE := 200.0
const ENEMY_BASE_SPEED := 90.0
const ENEMY_SPEED_RAMP := 0.4
const ENEMY_MAX_SPEED := 250.0
const ENEMY_CAP := 220
# Scales every contact and shot hit; tuned together with heal drops so HP swings rather than drains.
const ENEMY_DAMAGE_MULT := 0.85
const KNOCKBACK := 14.0


static func enemy_hp_scale(t: float) -> float:
	var x := maxf(0.0, t - ENEMY_HP_GRACE)
	return 1.0 + x / ENEMY_HP_RAMP + pow(x / ENEMY_HP_LATE, 2.0)


static func enemy_speed(t: float) -> float:
	return minf(ENEMY_MAX_SPEED, ENEMY_BASE_SPEED + t * ENEMY_SPEED_RAMP)


# Rings skip the special behaviours so a full circle of shooters never appears at once.
static func pick_enemy_kind(t: float, allow_special := true) -> String:
	var weights := {
		"penta": clampf((t - 35.0) / 70.0, 0.0, 0.3),
		"hepta": clampf((t - 80.0) / 90.0, 0.0, 0.2),
	}
	if allow_special:
		# Light variants arrive first, the standard ones mid-run, the heavy ones late.
		weights["dart"] = clampf((t - 25.0) / 50.0, 0.0, 0.1)
		weights["turret"] = clampf((t - 40.0) / 50.0, 0.0, 0.08)
		weights["dasher"] = clampf((t - 55.0) / 60.0, 0.0, 0.1)
		weights["shooter"] = clampf((t - 75.0) / 60.0, 0.0, 0.07)
		weights["lancer"] = clampf((t - 110.0) / 60.0, 0.0, 0.06)
		weights["battery"] = clampf((t - 120.0) / 60.0, 0.0, 0.04)
	var roll := randf()
	for kind in weights:
		roll -= float(weights[kind])
		if roll < 0.0:
			return kind
	return "tri"


# --- Spawning ---
static func trickle_interval(t: float) -> float:
	return maxf(0.22, 0.6 - t * 0.0025)


static func trickle_pack(t: float) -> int:
	return 1 + randi() % (3 + mini(3, int(t / 45.0)))


static func ring_interval(t: float) -> float:
	return maxf(4.5, 8.0 - t * 0.02)


static func ring_count(t: float) -> int:
	return mini(48, 14 + int(t * 0.15))


static func xp_to_next(level: int) -> int:
	var n := level - 1
	return XP_FIRST + n * XP_STEP + int(n * n * XP_CURVE)
