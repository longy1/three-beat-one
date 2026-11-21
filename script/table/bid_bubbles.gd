class_name BidBubbles
extends RefCounted
## 叫分对话气泡：各家叫分/放弃以带尾巴的标准气泡呈现于各自座位旁（指向该座位），
## 不再占用姓名版状态行。气泡停留到被更高叫分取代（更高分出现即清除所有低分
## 气泡，只留当前最高）；放弃气泡保留到拍卖结束或本人再次表态。叫分越大字号
## 越大（130→200 线性），气泡随字号自适应，封顶约中央空白牌桌 1/3 面积。
## 状态驱动（[码1.4]）：apply 全量幂等，由控制器 _refresh_seats 按引擎竞叫状态
## 调用（重连快照恢复同路径生效）；新局/拍卖结束由控制器 clear_all。

const FONT_MIN := 17   ## 底叫 130 的字号
const FONT_MAX := 44   ## 封顶 200 的字号
const FONT_PASS := 15  ## 放弃气泡字号
## 最大气泡尺寸上限（中央空白牌桌约 960×430 的 1/3 面积的等效上限）
const MAX_SIZE := Vector2(430, 180)
const PAD := 14.0          ## 气泡文字四周留空（≈半字号）
const TAIL := 12.0         ## 尾巴长度
## 气泡锚点（相对窗口比例 ×根尺寸）：气泡靠座位一侧、尾巴尖角贴近玩家面板
## （720p 基准：你=手牌区顶上方 8px、乙=面板左缘 12px、丙=面板底 6px、
## 丁=面板右缘 12px）——尾巴朝座位方向
const ANCHORS := {
	0: Vector2(0.419, 0.669),
	1: Vector2(0.678, 0.408),
	2: Vector2(0.419, 0.208),
	3: Vector2(0.159, 0.408),
}
## 尾巴方向（气泡相对座位的朝向）：0=朝下 1=朝右 2=朝上 3=朝左（键=座位）
const TAIL_DIRS := {0: 0, 1: 1, 2: 2, 3: 3}

var _bubbles := {}         # seat → Bubble
var _anchors := ANCHORS    ## 锚点表（尾巴尖角位置；手机分支由控制器覆写为 MobileLayout.BUBBLE_ANCHORS）


func setup(root: Control, anchors := ANCHORS) -> void:
	_anchors = anchors
	for seat in 4:
		var bubble := Bubble.new()
		bubble.name = "BidBubble%d" % seat
		bubble.seat = seat
		bubble.anchors = anchors
		bubble.z_index = 4
		root.add_child(bubble)
		_bubbles[seat] = bubble
	clear_all()


## 运行中切换锚点表（UI 分支切换：桌面 ANCHORS ⇄ MobileLayout.BUBBLE_ANCHORS）
func set_anchors(anchors: Dictionary) -> void:
	_anchors = anchors
	for seat in _bubbles:
		_bubbles[seat].anchors = anchors


## 全量幂等应用（控制器 _refresh_seats 每次刷新按引擎竞叫状态调用）：
## bids 为按座位下标的 [{ value, passed }]；highest 为当前最高叫分。
## 只有当前最高叫分的气泡在展示（低分已被更高分取代即消失——气泡停留
## 直到有人叫出更高的分数）；放弃气泡保留到拍卖结束；无表态座位隐藏
## （新局重置不留残影）。
func apply(bids: Array, highest: int) -> void:
	for seat in bids.size():
		if not _bubbles.has(seat):
			continue
		var b: Dictionary = bids[seat]
		if bool(b.get("passed", false)):
			_bubbles[seat].show_text("不要", FONT_PASS)
		elif int(b.get("value", 0)) > 0 and int(b.value) >= highest:
			var fs: int = FONT_MIN + int(round(float(int(b.value) - 130) / float(200 - 130) * float(FONT_MAX - FONT_MIN)))
			_bubbles[seat].show_text(str(int(b.value)), clampi(fs, FONT_MIN, FONT_MAX))
		else:
			_bubbles[seat].show_text("", 0)


func clear_all() -> void:
	for seat in _bubbles:
		_bubbles[seat].show_text("", 0)


## 气泡（程序化绘制：圆角矩形 + 指向座位的尾巴，Label 居中）
class Bubble:
	extends Control

	var seat := -1
	var anchors: Dictionary = BidBubbles.ANCHORS  ## 尾巴尖角锚点表（分支可覆写）
	var _label: Label
	var _style: StyleBoxFlat
	var _tail_dir := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.96, 0.94, 0.86, 0.96)
		_style.set_corner_radius_all(12)
		_style.set_content_margin_all(0)
		_style.border_color = Color(0.35, 0.3, 0.2, 0.8)
		_style.set_border_width_all(2)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_color", Color(0.2, 0.18, 0.12))
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		visible = false

	## 设置文案与字号（空文案 = 隐藏）；座位序号决定尾巴方向与锚点偏移
	func show_text(text: String, font_size: int) -> void:
		_tail_dir = BidBubbles.TAIL_DIRS.get(seat, 0)
		if text == "":
			visible = false
			return
		_label.text = text
		_label.add_theme_font_size_override("font_size", font_size)
		visible = true
		_layout()

	func _layout() -> void:
		var font: Font = _label.get_theme_font("font")
		var fs: int = _label.get_theme_font_size("font_size")
		var text_size: Vector2 = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var sz := (text_size + Vector2(PAD * 2, PAD * 2)).min(BidBubbles.MAX_SIZE)
		size = sz
		_label.size = sz
		var anchor: Vector2 = anchors[seat] * get_parent().size
		match _tail_dir:
			0:  # 尾巴朝下（你）：气泡在锚点上方
				position = anchor - Vector2(sz.x / 2.0, sz.y + BidBubbles.TAIL)
			1:  # 尾巴朝右（乙）：气泡在锚点左侧
				position = anchor - Vector2(sz.x + BidBubbles.TAIL, sz.y / 2.0)
			2:  # 尾巴朝上（丙）：气泡在锚点下方
				position = anchor - Vector2(sz.x / 2.0, -BidBubbles.TAIL)
			3:  # 尾巴朝左（丁）：气泡在锚点右侧
				position = anchor - Vector2(-BidBubbles.TAIL, sz.y / 2.0)
		queue_redraw()

	func _draw() -> void:
		if not visible:
			return
		var body := Rect2(Vector2.ZERO, size)
		draw_style_box(_style, body)
		# 尾巴与框一体化（接缝处无描边横线，填充整块连续）：填充三角的底边向框体
		# 内推进越过边框（盖掉接缝段的框描边），描边只走两条斜边、不走底边，起点取
		# 斜边与框外缘的交点——与框描边自然相接
		var cx := size.x / 2.0
		var cy := size.y / 2.0
		var t := BidBubbles.TAIL
		var hw := 8.0  # 尾巴底边半宽（避开圆角，偏中放置）
		var d := 4.0   # 填充底边推进框体的深度（越过 2px 边框）
		var ex := hw * t / (t + d)  # 斜边与框外缘交点到尾部中轴的距离
		var fill: PackedVector2Array
		var stroke: PackedVector2Array
		match _tail_dir:
			0:  # 朝下（底缘）
				fill = PackedVector2Array([Vector2(cx - hw, size.y - d), Vector2(cx + hw, size.y - d), Vector2(cx, size.y + t)])
				stroke = PackedVector2Array([Vector2(cx - ex, size.y - 1), Vector2(cx, size.y + t), Vector2(cx + ex, size.y - 1)])
			1:  # 朝右（右缘）
				fill = PackedVector2Array([Vector2(size.x - d, cy - hw), Vector2(size.x - d, cy + hw), Vector2(size.x + t, cy)])
				stroke = PackedVector2Array([Vector2(size.x - 1, cy - ex), Vector2(size.x + t, cy), Vector2(size.x - 1, cy + ex)])
			2:  # 朝上（顶缘）
				fill = PackedVector2Array([Vector2(cx - hw, d), Vector2(cx + hw, d), Vector2(cx, -t)])
				stroke = PackedVector2Array([Vector2(cx - ex, 1), Vector2(cx, -t), Vector2(cx + ex, 1)])
			3:  # 朝左（左缘）
				fill = PackedVector2Array([Vector2(d, cy - hw), Vector2(d, cy + hw), Vector2(-t, cy)])
				stroke = PackedVector2Array([Vector2(1, cy - ex), Vector2(-t, cy), Vector2(1, cy + ex)])
		draw_colored_polygon(fill, _style.bg_color)
		draw_polyline(stroke, _style.border_color, 2.0)
