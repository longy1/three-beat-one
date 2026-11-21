# 更新记录（doc/update.md）

> 本文档是全仓库**代码的行为变更史**，原代码注释中的更新记录类内容（日期戳、变更叙述、
> 新旧行为对照）统一迁入此处。2026-11-18 起为强制规范（doc/coding.md §2，test_architecture
> 机器守护）：**代码注释只描述当前行为与规则出处，禁止日期戳与变更记录**；规则笔误与
> 里程碑级决策仍归《三打哈-Godot工程计划.md》，本文档只收代码注释层的历史注记。
> 条目按日期倒序，新条目置顶；每条注明迁出前所在的文件。

## 2026-11-21

- TODO.md 牌桌表现层批次二实现（用户需求：修复 6 项 TODO、本地提交后清理，分三提交落地）：
  - **牌背重绘**（`script/table/card_widget.gd`、`script/table/info_sidebar.gd`、`test/test_components.gd`）：
    背面去「哈」字，新增 `CardBackPattern` 内部类程序化经典花背（浅色内缩圆角内框 + 45° 双向
    斜线菱形格纹 + 中央菱形徽章，斜线与内框矩形求交裁剪不出格）；`create/create_sized` 移除
    back_mark 参数（唯一显式传参方 info_sidebar 未叫主态同步）；牌背用例改断言「纹样存在 +
    无文字标记」
  - **主牌标识守卫自愈**（`script/table/game_table.gd`、`script/table/trump_reveal.gd`）：
    `_on_discard_required` 移除 `_last_trump_shown` 预标记、`_trump_reveal.play` 提前到
    `_refresh` 之前，落位回调记 `_last_trump_shown` 并 `set_trump`；`_refresh_top_bar` 守卫加
    `not _trump_reveal.active` 条件（飞行中跳过、打断后自愈重渲）；`TrumpReveal` 存 tween 引用、
    `clear()` kill——根治「落位回调丢失 + 引用比较永久跳过」的标识消失（旧版 `active` 标记声明未用）
  - **发牌逐张 + 排序平滑 + AI 挂起**（`script/table/deal_animator.gd` 重写、`script/table/game_table.gd`）：
    逐拍一张（TICK 0.2s / FLIGHT 0.18s，替代整轮飞入后一次性成坨），汇聚槽提前计算
    （发牌顺序紧凑行），落位 0.08s 淡入现身；展开前按目标位 x 升序 `move_child` 重排
    `_clump_holder` 子节点（途中遮盖 = 排序后遮盖）、各牌同长 EXPAND_DUR 平移；拍卖表态挂起：
    `_on_auction_required` 在 `_deal_active` 时仅刷新即返回、`_on_deal_done` 按引擎轮转补跑
    （下一局/game_start 先置 `_deal_active` 再触发引擎信号——旧版 `_on_next_game` 在信号后才置位）
  - **气泡尖角贴面板**（`script/table/bid_bubbles.gd`）：ANCHORS 调整——甲 (0.419,0.640)→(0.419,0.669)、
    乙 (0.520,0.408)→(0.678,0.408)、丙 (0.419,0.230)→(0.419,0.208)、丁 (0.316,0.408)→(0.159,0.408)
    （锚点即尾巴尖角，距玩家面板/手牌区缘 6~12px）
  - **手机版 UI**（`script/app_settings.gd`、`script/menu/settings_dialog.gd`、
    `script/table/game_table.gd`、`test/test_ui.gd`、`static/ui-mockup.svg`、字体子集重跑）：
    `AppSettings.mobile_ui`（"ui" 分区持久化）+ `is_mobile_device`（android/ios/web_android/
    web_ios）+ `effective_mobile_ui`；设置第三行「手机版 UI（调试）：关/开」（设置弹层用例
    2→3 按钮同步）；`game_table._apply_layout_mode`：手机版手牌区右缘 -220→-128（≈90% 屏宽）+
    信息栏默认收起 + 右上角「信息/收起」切换按钮；新增 `test_mobile_layout_mode`（含桌面还原口径）
  - **发牌期间隐藏手牌虚线框**（`script/table/hand_area.gd`、`script/table/game_table.gd`、
    `test/test_ui.gd`；用户报告截图）：汇聚/收拢/展开阶段牌未分区排序、双虚线框位与牌不对齐——
    动画期间整体隐藏（`HandArea.set_frames_visible`，测量渲染后即藏），`_on_deal_done` 放行
    真实渲染（排序完成）后再展现；新增 `test_deal_animation_hides_frames` 用例
  - **发牌汇聚行与实际手牌行同 y**（`script/table/deal_animator.gd`）：行基线由「手牌区
    中心上方 8px」改为取测量位任一牌的全局中心 y（HAND_BASE_Y 同排）——汇聚/收拢/展开
    与最终手牌位置完全同步，展开落位无纵向跳动（`_clump_target` 防御分支同口径）
  - **叫分气泡挂起至排序完成**（`script/table/game_table.gd`、`test/test_ui.gd`）：底叫 130
    此前在发牌动画期间即出现（`_refresh_seats` 状态驱动 apply 未被门控）——气泡 apply 加
    `not _deal_active` 条件，排序完成后随拍卖呈现一起出现；用例改断言「动画期挂起 →
    排序完成后 130 出现」，并以放大 `_ai_delay_scale` 挂起 UI AI 避免补跑竞速
  - **移除发牌飞牌动画、面板张数逐拍增长**（`script/table/deal_animator.gd`、
    `script/table/game_table.gd`、`test/test_ui.gd`；用户需求：只保留手牌一张一张变多）：
    删除中央到座位面板的背面飞牌（`_fliers` 池/`FLIGHT`/`_seat_target` 整体移除，
    中央牌叠保留作发牌来源示意），逐拍循环改为手牌在汇聚槽直接现身 + `on_tick(已发张数)`
    回调——控制器 `_deal_shown_count`/`_refresh_seats` 使各家座位面板张数从 0 张
    逐拍增长到 19 张（动画结束回归引擎权威值）；新增 `test_deal_animation_counts_tick`
  - **手机版 UI 重做为独立分支**（`script/table/mobile/` 新增 layout/top_bar/more_panel、
    `script/table/hand_area.gd`、`script/table/deal_animator.gd`、`script/table/action_bar.gd`、
    `script/table/bid_bubbles.gd`、`script/table/card_widget.gd`、`script/table/game_table.gd`、
    `test/test_ui.gd`、ui-mockup.svg；用户定夺：移动端是完全另一套 UI 规范，仅规则与流程复用）：
    顶栏当局信息 bar（局况/主牌小牌面/捉分 + 「更多」按钮）——局数/四家累计/手牌统计/
    设置/菜单收进 MobileMorePanel 居中弹层；大手牌 96×134 贴底、步距 40·12（用户调整：
    间距更大）、宽 ≈90% 屏宽；出牌十字居中、乙/丁贴缘、按钮 150×52；CardWidget 新增
    BAR 第四档（36×50 主牌槽）；HandArea/DealAnimator/ActionBar/BidBubbles 参数化
    （hand_card_size/spacing/base_y/button_min/anchors，桌面默认不变）；替换旧版
    「加宽+信息栏折叠」半套实现；`_apply_layout_mode` 变分支应用器（桌面原值捕获还原）；
    重写 test_mobile_layout_mode + 新增 test_mobile_more_panel；修复新组件两处
    （close 变量遮蔽方法名的编译错、_apply_layout_mode 开局 hands 未发时 _render_hand 越界）
  - **气泡尾巴与框一体化**（`script/table/bid_bubbles.gd`；用户报告接缝有描边横线）：
    尾巴填充三角底边向框体内推进越过边框（盖掉接缝段的框描边），描边只走两条斜边且
    起点取斜边与框外缘的交点——与框描边自然相接，接缝处整块填充无横线

## 2026-11-20

- TODO.md 批量实现（用户需求：把指定 10 项 TODO 全部实现后 push 并部署，过程与经验统一记录本文档）。
  分主题：
  - **AI 守门动态放宽**（`core/ai_play.gd`、`core/ai_policy.gd`、test/test_ai_policy.gd）：垫牌守门
    避让按庄家剩牌量三档——剩牌 >16 全量避让（旧行为）、9~16 只避让队友深清（≥4 张）的门、
    ≤8 守门解除自由垫牌（残局守门无意义）；`choose_play` 新增 `banker_cards` 参（缺省 -1 =
    未知保持全量口径，旧调用方/测试零改动），AiPolicy/服务端传 `engine.hand_count(banker_seat)`；
    `_teammate_shed_suits` 拆出计数版 `_teammate_shed_counts` 供深清判定（避免镜像实现）
  - **存储层升级**（`server/store.gd` 重写、test/test_store.gd 新增套件）：store.json 整文件 JSON →
    **单文件追加日志库**（SQLite 平替定位：纯 GDScript 无第三方依赖）——每次变更追加一行 JSON op，
    启动顺序回放重建内存态，行数超 256 压实为单行快照（临时文件 + rename 原子替换），末行残缺
    （写入中途崩溃）回放自动截断并自愈重写；旧版 store.json 首次载入自动迁移；接口面不变
    （record_room/add_scores/room_scores）并新增 live_rooms 三接口（save/clear/load，供房间恢复）；
    套件注册表 13→14 套件，run_affected.sh 补映射（store.gd → test_store+test_online、
    app_settings.gd → test_components）
  - **重连身份令牌化 + 占用文案**（`net/protocol.gd`、`net/net_client.gd`、`server/room_manager.gd`、
    `server/host_room.gd`）：客户端每实例生成会话令牌（32 位 hex，会话级防顶座凭据，非加密强度——
    服务定位为本地/可信小服），每条 hello 必带、hello_ok 回执签发后保存；服务端 hello 流程重排——
    同 token 命中存活房间成员即回房（掉线宽限与旧连接静默窗口都承接，无需再判静默时长，
    `TAKEOVER_STALE`/`takeover_stale` 整体废除）；同昵称但 token 不符 = 其他设备在使用，
    在线成员一律拒绝，文案「昵称已被占用」→「该昵称已在其他设备登录」（用例断言同步）；
    离线成员（宽限期）同昵称无令牌可承接——覆盖应用重启/页面刷新丢令牌的合法回归
    （等待扫描判离线 ≤ 探测周期，原来的 15s 接管静默阈不再需要）
  - **服务端进程重启不散房**（同批文件）：host_room 全量序列化（成员含令牌 + 引擎全量，
    牌走 Card.key() 串与协议同构）+ `restore_from`（成员离线、令牌保留、宽限计时重挂、
    `_resume_pending_turn` 按阶段重新调度 AI 代打/离线快托管）；RoomManager 启动时
    `_restore_rooms` 经 store.live_rooms 重建（新 store 实例 = 日志回放，端到端即真实重启路径）；
    每次成功变更即 `_persist()` 落盘、close 时 clear；测试 test_server_restart_keeps_rooms：
    销毁服务端 → 同端口同存储重建 → 房间恢复 → 客户端凭 token 自动重连 → 快照恢复 → 打完
  - **设置面板**（`script/app_settings.gd`、`script/menu/settings_dialog.gd` 新增，main_menu、
    info_sidebar 加入口，`script/table/hand_area.gd` 呈现感知）：两项设置——手牌区主牌框在左/右
    （框序对调）、牌点数从大到小/从小到大（花色分组从左到右不变）；AppSettings 静态状态 +
    ConfigFile user://settings.cfg 即时保存生效（cfg_path 可重定向供测试）；弹层程序化构建
    （遮罩 + UiStyle.center_anchor 居中 + 循环切换按钮 + 完成）
  - **便捷操作**（hand_area + game_table）：双击手牌区空白（未命中任何牌的条带）清空选择，
    双击牌桌空白（Background 层）同款；触摸设备两指单击 = 右键出牌——首指按下即快照当前选择
    （先于触摸模拟的鼠标点选副作用），第二指按下（至少一指在手牌区内）确认手势，两指全抬时
    恢复快照撤销模拟点选、出牌模式下提交 play_requested
  - **叫分对话气泡**（`script/table/bid_bubbles.gd` 新增）：各家叫分/放弃改以带尾巴的气泡呈现
    （你=手牌上方尾朝下、乙=面板左侧尾朝右、丙=面板下方尾朝上、丁=面板右侧尾朝左），
    姓名版状态行腾空；气泡全量幂等 apply（_refresh_seats 状态驱动，重连快照恢复同路径生效）——
    只有当前最高叫分的气泡在展示（低分被更高分取代即消失）、放弃气泡保留到拍卖结束、
    无表态座位隐藏（新局不留残影）；字号随分值 130→200 线性 17→44px，封顶约中央牌桌 1/3 面积
  - **发牌动画**（`script/table/deal_animator.gd` 新增）：开局（单机开局/下一局、联机 game_start；
    重连快照不播）中央出现背面牌叠 → 19 轮按 4 张/轮背面飞入各家（闲家到座位面板隐没）→
    我的牌翻正面逐张淡入、按发牌顺序挤成一坨（未排序未分常主）→ 两边向中间收拢 →
    按牌对号展开到真实牌序布局（目标位取自 HandArea 测量渲染的真实卡牌位——控制器先渲一次
    并隐藏真实牌面，动画结束回调重渲放行）；播放期间 `_render_hand` 统一挂起（`_deal_active`）；
    表现层不阻塞对局（test_deal_animation_non_blocking）；speed 缩放供测试（ui_test_base =80）
  - **联机菜单最近成功连接**（`script/menu/online_menu.gd`）：连接成功（hello_ok）即记录规范化地址
    （去重置顶、封顶 5 条、ConfigFile 落盘），地址框下方渲染条目按钮、点按填入地址框
    （cfg_path 可重定向供测试）
- 经验/踩坑记录（本轮）：
  - `run_tests.gd --tests` 多值过滤把无类型 Array 直接赋给 `Array[String]`，解析期报错令
    `_initialize` 中断、进程永不退出（表现为「测试卡死」）——修为逐个 str() 转换；测试协程内
    运行时错误会静默中断该用例且被计为通过（框架 await 对中断协程立即返回），test_components
    三处旧场景路径（重构前 `res://scene/seat_panel.tscn`）因此长期静默空转——修为
    `scene/table/` 并借此确认用例真实跑通
  - UI 直驱引擎的测试与牌桌自身 `_run_ai` 计时存在竞速：用例中插入 `await tree_pause()` 再按
    固定座位提交会被 AI 抢先——新用例要么同帧完成全部提交（无 await），要么自适应当前回合/
    用结算历史做健壮断言；叫分气泡用例曾因「dealer 在 _deal 之前读取」拿到随机局的庄家而假失败
  - 令牌化后自动重连「首试即回房」，服务端未及扫出掉线时不再有 member_offline 广播——
    test_client_auto_reconnect 的离线/上线 presence 断言移除（行为更优，避免竞态假失败）
  - store 每次追加 `flush()` 强制刷盘在高频对局动作下开销过大（联机套件 95s→205s），
    改为 close 即落盘后回到 98s
  - ZCode 内嵌浏览器（IAB）验收时页面非前台会节流 rAF：游戏画面停滞、状态不推进，均在与页面
    交互的瞬间恢复——为环境节流而非游戏缺陷（headless smoke 完整跑通一局、同一 await 计时
    机制的 AI 节拍在交互间隙正常推进）；自动化验收需周期性保持页面活跃，真实用户前台标签页不受影响
  - gh API 复刻推送链式多提交时需按提交 diff 出变更文件清单建 blob——`git diff --name-only`
    默认 quotePath 会把中文路径转义成 `"doc/ä¸..."` 字面量，与 ls-tree -z 的原始
    字节路径不匹配，中文名文件的变更被漏建 blob（远端引用悬空 422）——diff 加
    `-c core.quotePath=false` 输出原始路径即愈；Git 对象按内容寻址，重跑幂等
- 视觉稿 static/ui-mockup.svg 同步：丙/丁叫分气泡示意（姓名版状态行腾空）、信息栏【设置】按钮、
  联机菜单「最近成功连接」条目与令牌化文案、联机牌桌态注记参数更新（宽限 180s/心跳 60s）、
  发牌动画流程注记——原 static/ui-mockup.svg
- 配套文档同步：AGENTS.md（目录/套件计数/已知简化）、doc/coding.md（§1.12 令牌化、§4 气泡/发牌
  动画/设置/手牌交互、§5 新套件）、README.md（联机重连口径与新功能）、工程计划（技术决策与
  实施记录）、TODO.md（10 项勾选）——各文件本体

## 2026-11-19

- 测试基建提速与分级（用户需求：①分析全量测试性能并优化、考虑并发；②push 前才跑全量、
  本地 commit 只跑受影响；③日常开发默认本地提交、显式要求才 push）：逐套件/慢用例计时
  诊断（[suite]/[slow] 行）显示 89% 耗时在 test_online 联机回环（80s，完整对局类用例绑
  服务端缩放节拍与宽限等待，轮询收紧无感）；**并行分片**——run_tests.gd 接受用户参数
  （--suite/--tests/--shard=k/n/--result-file），分片按「文件名::用例名」稳定哈希（新用例
  自动纳入分片，零维护），test_online 端口/存储按 TEST_PORT_OFFSET 偏移（分片进程不撞
  端口）；新增 run_tests_parallel.sh（默认分片 = 逻辑核数封顶 8，7700X 实测 6 分片墙钟
  ~24s vs 顺序 ~100s，4.2×）与 run_affected.sh（改动文件→套件映射，触测试基建/全局配置/
  未知路径自动转并行全量）；AGENTS.md §2 命令与验证顺序、§4 本地提交约定（默认本地
  commit 不 push，push 前并行全量）——原 test/test_framework.gd、test/run_tests.gd、
  test/test_online.gd、test/run_tests_parallel.sh（新）、test/run_affected.sh（新）、
  AGENTS.md §2/§4、doc/coding.md §5
- JOKER 字母改等宽字体（用户反馈：五个字母看着没对齐，建议等宽字体）：根因是字母用 Noto 的
  比例拉丁字形——各字形墨迹中心相对步进中心有偏差，居中盒对齐的是步进中心不是墨迹中心，
  竖排即错位；等宽拉丁字体无 ♠♥♣♦，故角标花色维持 Noto+居中方案不变。新增第二字体
  `font/RobotoMono-Regular.subset.ttf`（仅 J/O/K/E/R 五字形，1.2KB，Apache-2.0，源字体缓存
  build/_font_src/，重切命令记入 coding.md 资源与字体节），王牌字母 Label 加 font override；
  渲染复核竖排墨迹成列，147/147——原 script/table/card_widget.gd、font/（新增子集+.import）、
  doc/coding.md 资源与字体节
- 手牌命中范围改露出条带（用户报告：点击和拖动选牌会意外选中隔一张的牌，要求除最右一张外
  只把露出部分作为可点范围）：根因双处——拖动的 `_input` 全局命中取「最左包含」的牌（鼠标在
  牌 i 的可见区命中被压住两张的 i−2，正好隔一张）；点击虽有顶层路由但卡牌整张矩形可收输入，
  重叠区边界易误触。改为卡牌控件 `mouse_filter IGNORE`，点击与拖动统一走 `HandArea._hit_card_at`
  条带命中（每张牌只有到下一张牌左缘的露出部分可命中，各框末张整张；`_gui_input` 分发点击），
  `test_components` 补条带命中回归用例（147 用例）；连带修复 `to_local()` 误用（Control 无此
  Node2D 方法，曾致 HandArea 编译失败拖垮全部牌桌用例）——原 script/table/hand_area.gd、
  test/test_components.gd、doc/coding.md §4
- JOKER 字母列贴角 + 牌堆弹层假失败根治（用户反馈：JOKER 要贴近左上角；随发现牌堆延迟隐藏
  用例在后台负载下假失败）：王牌字母列 y 从纵向居中改**贴左上角起排**（右列镜像贴右下角，
  上下边距 3px 与普通牌角标一致）；test_ui 牌堆延迟隐藏用例的检查点由 0.05s 定时等待改
  **单帧等待**（await process_frame）——后台负载的慢帧会把检查恢复与 0.1s 隐藏计时器挤进
  同一帧造成假失败，单帧等待与负载无关且仍能抓住「移出即隐藏」回归；coding.md §5 收
  「计时敏感断言用单帧等待」规范——原 script/table/card_widget.gd、test/test_ui.gd、
  doc/coding.md §4/§5
- 中央花色回正中 + JOKER 字距收紧（用户反馈：①中央图标看着不居中；②JOKER 五字母太散、
  字号不必与点数一样大，要贴实牌的紧凑感）：中央花色去掉 0.30 下沉偏移回牌面横竖正中
  （字号维持 26/18/22）；JOKER 字母字号 12/9/10→11/8/9、列高 96/72/82→65/50/55
  （整列纵向居中，五字母间距紧凑）——原 script/table/card_widget.gd、doc/coding.md §4
- 王牌去「大/王」角标，改经典小丑牌版式（用户反馈：不要大王小王字样，正常 joker 牌就是
  JOKER，并给出实牌参照——左右两列竖排 JOKER、右列倒置、红黑分大小王、中央小丑）：
  王牌不再绘制角标，JOKER 字样由单列改**左右两列**（右列整列 180° 倒置，逐字母落位镜像），
  像素小丑移到正中；大小王区分仅靠红黑着色（字母与小丑帽同色），与实牌惯例一致；
  普通牌角标/镜像不受影响——原 script/table/card_widget.gd、doc/coding.md §4
- 角标重做 + 旋转对称 + 中央花色调小（用户三点需求：①花色标记与点数不在一条竖线上、
  建议试等宽字体；②中央花色离角标太近应调小；③卡牌应旋转对称、右下角补标记）：
  角标由单 Label「点数\n花色」拆成**每行一个 Label、各居其半区水平居中**——Noto 里花色字形
  全角、点数半角，左对齐必错位，居中才能同轴（等宽拉丁字体不含 ♠♥♣♦ 字形，不采用）；
  卡牌**旋转对称**：右下角同款角标 180° 镜像（pivot_offset=size/2 + rotation 180°），
  王牌角标「大/王」「小/王」同样镜像；中央花色字号 34/26/30→**26/18/22** 并按
  `CENTER_TOP_RATIO` 0.30 下沉（远离上下角标）；像素小丑移到右上（避开右下镜像角标）；
  test_components 角标断言同步新结构（点数/花色分行 + 花色 ≥2 处）——
  原 script/table/card_widget.gd、test/test_components.gd、doc/coding.md §4
- 王牌牌面竖排 JOKER 字样 + 像素小丑（用户需求：大王/小王改竖排 Joker 字样；随后从 3 张
  网络示例图中选定 Balatro 像素小丑作设计参考，程序化重绘不引入图片素材）：`CardWidget`
  王牌面 = 左列竖排 J→O→K→E→R（大王红/小王黑沿用角标着色）+ 右侧 `PixelJester` 8×11 色块
  网格小丑（黄铃帽色区分大小王：大王红帽/小王黑帽；白脸蓝身；整簇先铺深色底再叠色块＝
  像素风描边）；字母逐个 Label 落位（列高五等分，间距确定）——单 Label 的 \n 换行受主题行距
  影响实测行高 ≈1.8× 字号，五行必溢出牌底；角标同步拆「大/王」「小/王」两行竖排（与普通牌
  「点数上花色下」同构，此前大王/小王角标横排两字在紧凑重叠下被后牌盖住）。JOKER 为 ASCII
  字母，子集字集本就含可打印 ASCII，无需重跑字体子集；三档尺寸窗口直摆截图复核
  （test_components 大王红色断言不变仍通过）——原 script/table/card_widget.gd、doc/coding.md §4
- 手牌与出牌紧凑化（用户需求：①手牌再紧凑些；②出的牌照手牌摆法重叠摆、不要摊成全宽横排）：
  手牌相邻牌步距上限 `HandArea.SPACING_MAX` 40→24（露出条宽 = 步距，宽度不足仍向
  SPACING_MIN 8 收紧）；出牌区各家组合弃 HBoxContainer 平铺（separation 4）改手工
  重叠横排——步距直接引用 `HandArea.SPACING_MAX` 保持两处同口径，出牌行与卡牌控件
  均 `MOUSE_FILTER_IGNORE`（重叠区不挡点击）；静态视觉稿 ui-mockup.svg 同步
  （手牌双框收窄 + 牌面条带示意、四家出牌改重叠示意）；test_ui 出牌区断言由
  「数 HBoxContainer 行」改为「数 TrickArea 内真实 CardWidget 牌面」（按内容而非
  结构计数，摆法变动不再破坏断言，BottomCards 翻底弹层按名排除）——
  原 script/table/hand_area.gd、script/table/game_table.gd、test/test_ui.gd、
  static/ui-mockup.svg、doc/coding.md §4
- 卡牌移动端触控调整（用户需求：①花色点数同行改竖排以缩短牌间距；②适当加大牌尺寸，
  兼顾画面与主流移动设备触摸目标）：三档尺寸上调——NORMAL 60×86→72×100、MEDIUM
  50×72→60×86、SMALL 44×64→52×76（iPhone 横屏 letterbox 缩放 ≈0.54 下手牌 ≈39×54pt）；
  角标改竖排（点数上、花色下；王无花色仅单字），`Card` 拆出 `rank_label()`/`suit_label()`
  供角标取值；字号随牌放大（中心 30/22/26→34/26/30、背面哈 32/24/28→36/28/32）；
  连锁同步：信息栏 TrumpSlot 场景 min size 44×64→52×76、出牌区/手牌/揭主飞牌均经
  SIZE_* 常量自动跟随；手牌区布局数学复核（HandRow 高 118px 容纳 NORMAL+BASE_Y，
  27 张扣底阶段最小间距仍可行）——原 core/card.gd、script/table/card_widget.gd、
  script/table/info_sidebar.gd 关联场景 info_sidebar.tscn、
  script/table/trick_history_panel.gd 注记、test/test_components.gd（竖排角标断言）
- iOS 视口看门狗（用户报告：iOS Safari 转屏/回前台后画布偏移黑边——Safari 视口在地址栏
  收合/转屏后分多帧才稳定甚至不触发 resize，Godot 画布按旧视口定格）：export_presets.cfg
  的 html/head_include 追加 iOS UA 门控脚本——orientationchange/visualViewport resize/
  visibilitychange(可见) 触发 scrollTo(0,0) 复位页面偏移并合成 window resize（250/700/
  1500ms 三拍补发），让引擎按稳定后的视口重算画布；仅补发引擎自身监听的事件，无此前
  rAF 垫片的反作用风险；桌面/安卓路径被 UA 门控跳过零影响；产物 grep 验证注入生效——
  原 export_presets.cfg、README.md 移动端节、doc/coding.md §3 ⑥、TODO.md iOS 项
- 居中弹层锚点按场景取（用户报告：房间界面退出时累计分数弹窗歪斜——硬编码桌面十字锚点
  在菜单/大厅场景无意义）：新增 `UiStyle.center_anchor(node)` 统一规则——当前场景为联机
  牌桌（挂 `_net`）用桌面十字中心、非牌桌场景（主菜单/联机菜单/房间大厅）用屏幕正中；
  ScoresDialog/ReconnectOverlay/大厅补电脑确认框三处改走该规则；回归用例补进
  test_ui_online_table（牌桌内=桌面锚点、主菜单下=屏幕正中两断言）——原 script/ui_style.gd、
  script/menu/scores_dialog.gd、script/menu/reconnect_overlay.gd、script/menu/room_lobby.gd、
  doc/coding.md §4、test/test_online.gd
- 换行符统一（用户需求：审查中反复出现换行符修改，保持 AI 写盘与仓库一致）：根因是 Windows
  默认 `core.autocrlf=true`（Git 安装器写入系统级配置）在 checkout 时把仓库 LF 注入成 CRLF
  ——仓库 blob 本就全 LF，工作区却 57 个 CRLF 与 AI 写盘的 LF 混杂；新增 `.gitattributes`
  （`* text=auto eol=lf` 强制 LF；`*.bat -text` 保持仓库原样；otf/png 等显式 binary）+
  本仓库 local `core.autocrlf=false`/`core.eol=lf`（不动全局配置）+ 工作区 55 个文本文件
  CRLF→LF 原地归一（内容零变化仅行尾；bat 保持仓库原样不动；git checkout 类命令对内容
  等价文件不写盘，故用 sed 原地转换）+ `git add --renormalize` 重归一 index 消除假 M——
  原 .gitattributes（新增）、.git/config（local）、55 个工作区文件（仅行尾）
- 大厅选座（用户需求：座位旁加落座按钮，点击挪到那个位置）：协议新增 `sit { seat }`（大厅
  内落座——空位挪入、他人占座互换，成员字典整体对调、昵称/离线态随人走，对局中拒绝）；
  房主座位跟人不跟座（owner_seat 按房主昵称推导，开局/下一局权限校验本就按昵称不受影响）；
  大厅成员行右侧加【落座】按钮（自己所在行不显示、对局中不显示，room_state 广播驱动刷新；
  视觉稿大厅区域同步）——原 net/protocol.gd、server/room_manager.gd（_on_sit）、
  server/host_room.gd（sit/owner_seat）、net/net_client.gd（request_sit）、
  script/menu/room_lobby.gd（_member_row 行改造）、static/ui-mockup.svg、
  test/test_online.gd（test_seat_sit）
- 同昵称快速接管与昵称保留口径（用户需求：断连后凭昵称重建连接，昵称为其保留重连窗口）：
  服务端 `_on_hello` 增加「静默在线成员接管」分支——同昵称 hello 命中在线成员且其 peer
  静默超阈（TAKEOVER_STALE=15s，客户端 5s 心跳 ×3）时释放旧 peer 映射并立即回房，覆盖
  「断连未被扫描判出（半开 TCP 发送不报错）」窗口期内重连首试被「昵称已被占用」阻塞约
  60s 的问题；昵称保留口径明确为「保留窗口 = 重连窗口」（宽限期内随房间保留，重连分支
  先于占用拒绝；房间解散/主动退出或未进房连接静默清理后才释放复用）——原
  server/room_manager.gd（_on_hello/_peer_stale/_release_peer）、net/protocol.gd 注释、
  test/test_online.gd（test_nick_takeover_on_stale）、doc/coding.md §1.12/§5、
  AGENTS.md §6、README.md 联机段

## 2026-11-18

- 联机断线重连闭环（用户需求三项）：①服务端心跳判定阈值 15s→60s（Web 后台标签页暂停
  主循环、心跳停发但连接由浏览器维持，真断连靠探测发送失败即时判定）；掉线成员经旧连接
  发来的任意消息按 pid 匹配离线成员直接复活回房（room_manager._try_revive，无需重新
  hello）；②客户端自动重连：NetClient 掉线（在房间/对局中）不再直接弹窗回菜单，改进
  等待重连弹层（script/menu/reconnect_overlay.gd 新增）+ 3s 定时重试（窗口 150s 与服务端
  宽限对齐），成功依据 hello_ok 新增 rejoined 字段；回前台补发 hello（FOCUS_IN）为 Web
  后台恢复的复活入口；期间 ERR 视为「服务端尚未扫出掉线」留待下轮重试（昵称占用未释放
  的竞态窗口自愈）；服务端离线宽限 120s→180s（用户定夺 3 分钟）、member_offline 附带
  grace 秒数、离线座位回合 5s 快托管（他人不必干等）、回连时在走的回合计时重挂满正常
  时长；牌桌/大厅新增掉线等待与重连提示（member_presence 信号）；③底牌浮层遮挡修复：
  扣底阶段底牌展示 z_index 50→1（只比桌面高一层），出牌历史面板/牌堆弹层显式 z=10
  ——原 server/room_manager.gd、server/host_room.gd、net/protocol.gd、net/net_client.gd、
  script/menu/reconnect_overlay.gd（新增）、script/menu/room_lobby.gd、
  script/table/game_table.gd、script/table/trick_history_panel.gd、script/table/pile_viewer.gd、
  test/test_online.gd（自动重连/复活/快托管三用例；既有 drop 用例经 auto_reconnect=false
  保持旧路径）、test/test_ui.gd（底牌层级回归用例）
- Web 壳清理与主菜单文案：移除导出壳注入的左上角诊断角标 #sbd-diag（墙钟/rAF/分辨率
  统计，CSS 规则、DOM 创建与计数循环整体删除，一并清掉历史遗留的残串行；全屏按钮与
  iOS 提示保留）；主菜单标题「三打一单机版」改「三打一」——原 export_presets.cfg
  （html/head_include）、scene/menu/main_menu.tscn
- 昵称改在线占用制：只与同时在线的玩家互斥（活跃 peer；存活房间成员含离线宽限期经
  重连分支承接），掉线经扫描清理即释放、可随时复用；废除全局永久注册表（store.gd 删
  players 表与 has_player/register_player，载入旧文件即丢弃遗留 players 键；房间留档
  与累计分持久化不变）——原 server/room_manager.gd（_on_hello 拒绝条件）、
  server/store.gd、server/server_main.gd 与 server/host_room.gd 注记、
  scene/menu/online_menu.tscn（标签文案）、test/test_online.gd（存储用例去注册断言、
  昵称用例改在线占用语义并新增掉线释放复用断言）
- 队友无主后垫牌迭代：闲家有主但队友已公示无主时，主牌分（带分主牌）降为可垫档、
  无分大牌主照旧保留（主牌集中在我与庄家手中，小分主守不住）——原 core/ai_play.gd
  垫牌排序新增 mate_void 通道
- 闲家无主垫牌迭代：无主时 5 与无分牌同档尽早甩出（留 5 无赢张价值）；聚焦清一门
  「队友已垫大牌（≥K）且本家无赢张（顶 ≤Q）」的副花色（守门对该门失效）——原
  core/ai_play.gd 两处垫牌断言与甩打轮断言按新基准更新（♥5 不再受无分牌保护）
- 叫分扫荡概率模型（`AiBidding.sweep_prob`）落地：假想定主估「以对/拖抽干闲家主牌」
  概率，上探档 P≥0.30/0.60/0.85 → 165/180/200；特批参与 P≥0.5 且 EV>−2.0；极端
  P≥0.85 无视 EV 放手（探 200 与放宽参与均为用户定夺）。原注记散于
  core/ai_bidding.gd、test/test_ai_policy.gd
- 行为翻转：165/180 档旧版「全负 EV 一律放弃」→ 扫荡概率高的手逐级跟叫（满编四王手
  跟至封顶 200；对手加叫按 Δ=(叫分−130)×0.04 折算常主证据即时压回）。原注记于
  test/test_ai_policy.gd
- 校准复跑验证：出牌层自 83cb294 换表后零改动，4200 局满格复测 24 格差异均在采样噪声
  内 → 基线无漂移，BID_CALIB 维持不动；校准工具样本量 60→200 局/格（详见工程计划
  「校准复跑验证」节）
- 规范建立：代码文件禁更新记录式注释，历史注记迁入本文档（本条即迁出动作本身）
- 文档引用令牌制落地：代码注释引用文档一律用短令牌（[规N]/[码N]/[构N]/[史]/[划N]），
  不再写完整路径——注册表单一事实源在 AGENTS.md §5（代理每次会话自动加载 = 天然解码表），
  `test_doc_tokens_valid` 校验令牌已注册且节号真实存在于目标文档「## N.」标题；原 12 处
  路径式引用迁为令牌（ui_style / trump_rank_picker / hand_area / table_view / store /
  host_room / test_components / test_architecture / ui_test_base / test_ui）

## 2026-11-17

- AI 角色化策略迭代（core/ai_play.gd、test/test_ai_policy.gd）：
  - 闲家提前下分门槛 `_unseen_can_beat`：未现身牌中仍有同型能压过庄家当前牌才下分
    （单张比牌力 / 对子同身份两张更高 / 拖拉机相邻两对更高；副牌轮未现身主牌同型可杀）
  - 庄家扣底平衡细化：保留顶牌最强（平手取更长）且 ≥2 张的副花色整门作赢张引擎，
    分牌随门保留；常主不扣
  - 闲家垫牌守门协调 `_teammate_shed_suits`：队友以垫牌角色累计 ≥2 张的副花色视为
    「在清该门」，本家自由垫牌避开同门
  - 垫牌花色牌力三档分级：顶 ≤10 尽早清理 / 顶 J~Q 中性 / 含 K~A 更多保留；
    分级优先于守门避让与逐张牌力
  - 领出角色化重写 + 增补：7.3 甩牌（三家公示无主甩主牌）、庄家持有花色加成（持续消耗
    其副牌）、无组合时单张试探（确定剩牌领该门最大带分试探 / 不确定领 A/Q 大牌）
  - 甩牌上限（用户定夺：太多看不清）：一次最多 4 张，主牌更多时下一轮继续甩
- 叫分平滑化：EV 校准表只定「愿叫上限档」，实际叫分一律当前最高 +5 逐轮递进（弃跳档）
  （core/ai_bidding.gd）
- 叫分重校准：守门协调 + 牌力分级 + 下分门槛细化出牌策略下 ×2 轮加权定稿 BID_CALIB
  （强牌 130/135/150 = +0.17/+0.15/+0.33，150 档最优；165+ 明确负，愿叫上限档 150）
- 规则 7.3 无主公示/主牌甩打增补（core/follow_rule.gd、core/game.gd、core/trick.gd、
  test/test_follow.gd、test/test_game.gd）：领出者之外三家均无主牌时可一次甩出多张
  主牌单牌，等同连续单张；甩打轮其余三家垫相同张数
- UI（script/table/）：
  - 揭主双飞 `TrumpReveal`：叫主完成瞬间主 R 牌面与皇冠同现中央，牌面飞至信息栏
    主牌位，落位回调才把主牌放进信息栏（此前即时出现无过程）
  - AI 庄家扣底节奏 `AI_DISCARD_DELAY=1.0`：关键决策点多停约 1 秒，太快看不清翻底
  - 皇冠人类落点 `CROWN_HUMAN_TARGET=(0.108,0.749)`：手牌上方按钮行、牌堆按钮右侧，
    不遮挡手牌（原落点遮手牌）
  - 「牌堆」入口移至「历史」右侧同一行（原皇冠下方会遮挡手牌）；`PileViewer` 重做：
    原按座位悬停/钉住的自身历史弹层移除，悬停粘滞 `HIDE_DELAY=0.1s`（用户定夺 0.1s）
  - `SeatPanel` 悬停查看历史路径移除，出牌历史改走 `TrickHistoryPanel`（重做：十字
    摆位一轮四家出牌、翻轮次四按钮、✕/点击窗口外遮罩关闭、状态驱动就地收敛页码）
- 修复/回归（test/test_ui.gd、test/test_components.gd）：
  - `HandArea.render` 剪除陈旧选中引用：「牌不在手中」整局卡死（快速连打/暂停期出牌
    的渲染竞争留下已打出牌的引用，后续提交全被 NOT_IN_HAND 拒绝）
  - `VoidStamp` 用 `top_level` 脱离布局树：曾是 PanelContainer 直接子件被整面填充布局
    拽到左上角压住姓名
  - 底牌入手即选中（人类庄家翻底后 `select_cards(engine.kitty)` 预选）
  - 选牌跨轮保留：`begin_select` 仅模式切换时清空，同模式续轮不清
  - 出牌提交成功后按钮立即隐藏：结算停留期内下一个 `*_required` 处理器 await 挂起，
    旧「出牌」按钮曾挂满整个停留期且可再点

## 2026-11-16

- 规则修订（R=A 特例）：R 为 A 时 A 即常主，同花色的 A 对与 2 对相邻（A~2 连，含副
  花色 AA22 与主花色 AA22 同判合法）；AA22 在其花色的同类拖拉机中排最小（如主牌
  AA22 < 主牌 7788）。原注记于 core/combo.gd、test/test_combo.gd
