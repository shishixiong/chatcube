# 小词城 3D 英语探索 — OpenDesign 设计提示词

> 用法：把下面「提示词正文」整段复制给 OpenDesign。它会输出一个可直接放进
> `entry/src/main/resources/rawfile/city3d/` 的低多边形 3D 小城市原型。
> 参考实现：`entry/src/main/resources/rawfile/room3d/`（小词屋 Word Room）。

---

## 提示词正文

你是一名擅长「儿童教育 + 低多边形 3D 交互网页」的产品设计师与前端工程师。请设计并完整实现一个名为 **「小词城 Word City」** 的 3D 英语探索小城市，作为 HarmonyOS 应用中「小星英语老师」的互动教学卡片（Web 容器内运行，three.js 本地渲染）。

请先给出一页纸的设计说明（场景分区、镜头、交互流、性能策略），然后**直接输出完整可运行的代码文件**，不要只给大纲、伪代码或 TODO。所有文件必须能离线运行，不依赖任何网络资源。

---

## 1. 产品背景与质量基准

已有参考产品「小词屋 Word Room」：一个可 360° 旋转、可点击的低多边形 3D 全屋，包含客餐厅、厨房、儿童房、主卧、生活阳台共 76 件可点击物品；点击物品弹出单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句），支持英文标签、词汇表、收集进度点阵、原生 TTS 发音、房间镜头切换。它运行在 HarmonyOS ArkWeb 中，全程离线，移动端保持流畅。

**「小词城」要达到同等或更高的完成度**，但场景从室内扩展到一座有生命力的微型城市：

- 低多边形、暖色、圆润、儿童友好；
- 有道路、建筑、车辆、行人、红绿灯，场景是「活的」；
- 50 个可点击英文单词，全部能开口读、能看解释；
- 交互与 room3d 同构：旋转 / 缩放 / 平移、点选、单词卡、标签、词汇表、进度、镜头分区；
- 讲解型体验，**不判对错、不授星、不弹测验**。

---

## 2. 一句话概念

> 一座手掌大小的低多边形小城：一条东西向主街穿过中央广场，学校、医院、公园、超市分布在四个街区；公交车、汽车、自行车和行人沿道路循环行驶，路口红绿灯按真实节奏切换；孩子点一点建筑、车辆或小动物，就能听到它的英文名字，并把 50 个单词收进「小词城护照」。

---

## 3. 场景布局（世界坐标，单位：米，Y 轴向上，北 = -Z）

### 3.1 地图规格

- 总范围：`x ∈ [-60, 60]`，`z ∈ [-45, 45]`，约 120m × 90m 的方形街区。
- 地面：低多边形草地基底 + 浅色人行道 + 深灰沥青路面；边缘用矮树篱 / 围栏收边，避免「漂浮的岛」。
- 主街（Main Street）：东西向，`z ∈ [-4.5, 4.5]`，双向四车道 + 两侧各 2.5m 人行道 + 北侧 1.5m 绿色自行车道。
- 学校街（School Street）：南北向，`x ∈ [-14, -6]`。
- 公园路（Park Road）：南北向，`x ∈ [31.5, 38.5]`。
- 北环路：东西向，`z ∈ [-35, -29]`，把四个街区连成一个可循环的交通环。
- 河流：沿南侧 `z ∈ [33, 40]` 东西向流过，宽 7m；公园路在 `x ≈ 35` 处通过一座小桥跨河。
- 中央广场：主街南侧 `x ∈ [-8, 8]`、`z ∈ [5, 16]`，铺浅色地砖，中央放喷泉。

### 3.2 四个街区

| 街区 | 位置 | 主要内容 |
|------|------|----------|
| 医院区（西北） | `x -60..-10, z -45..-5` | 医院、消防站、救护车、医生、护士、消防员 |
| 学校区（东北） | `x -10..60, z -45..-5` | 学校、图书馆、校车、自行车、老师、学生、学校门口斑马线 |
| 商业街（西南） | `x -60..-10, z 5..32` | 超市、面包店、咖啡馆、邮局、警察局、电影院、公交站 |
| 公园区（东南） | `x 8..55, z 7..32` | 公园、池塘、游乐场、树、花、草地、小船、鸭子、狗、风筝 |

### 3.3 建筑与地标（可按比例微调，但保持相对关系）

| 对象 | 大致位置 | 形态建议 |
|------|----------|----------|
| 医院 hospital | `(-42, -22)` | 4 层白色 / 薄荷色体块，红色十字招牌，门口有救护车车位 |
| 消防站 fire_station | `(-22, -30)` | 2 层红砖色，两个卷帘车库门，门口停消防车 |
| 学校 school | `(14, -24)` | 3 层奶油色 + 珊瑚色屋顶，钟楼、旗杆、操场和校门 |
| 图书馆 library | `(36, -30)` | 2 层浅蓝色，拱形窗，门口有书形招牌 |
| 超市 supermarket | `(-40, 16)` | 2 层大盒子，红黄条纹雨棚，购物车和蔬果堆头 |
| 面包店 bakery | `(-24, 12)` | 1 层小屋，条纹遮阳篷，烟囱冒小烟圈，橱窗摆面包 |
| 咖啡馆 cafe | `(-20, 22)` | 1 层，户外圆桌和遮阳伞，门口立式菜单牌 |
| 邮局 post_office | `(-50, 8)` | 2 层，蓝色邮筒，包裹堆 |
| 警察局 police_station | `(-12, 15)` | 2 层，蓝白配色，门口停一辆警车（非单词装饰） |
| 电影院 cinema | `(48, 14)` | 2 层，竖排灯牌、售票亭、门口红地毯 |
| 公交站 bus_stop | `(10, 5.5)` | 透明顶棚 + 长椅 + 站牌 + 时刻表 |
| 中央喷泉 fountain | `(0, 10)` | 三层圆形水池，水柱粒子循环 |
| 公园 playground | `(18, 20)` | 秋千、滑梯、跷跷板、沙地 |
| 池塘 pond | `(38, 22)` | 椭圆水池，睡莲、芦苇、三只鸭子 |
| 小桥 bridge | `(35, 36.5)` | 木色拱桥跨河，栏杆可点击 |
| 河流 river | `z 33..40` | 半透明蓝色低多边形水面，缓慢流动的波纹 |

### 3.4 街道家具与装饰（大量增加「城市感」细节）

非单词装饰（不可点击，但必须存在）：红白路缘石、井盖、消防栓、交通锥、停车位标线、车道箭头、公交站时刻表、店铺遮阳篷、屋顶水箱、烟囱、空调外机、阳台花箱、路灯灯头、电线杆和电线、广告牌、横幅、垃圾桶内袋、长椅木纹、树池、灌木、花坛、栅栏、河边护栏、云朵、远处飞鸟、气球小贩（可放在广场边缘，作为氛围）。

可点击的 50 个单词对象见第 5 节。每个可点击对象都要有独立的、略大于自身轮廓的隐形 hitbox，保证孩子容易点中。

---

## 4. 动态系统（城市必须「活」起来）

### 4.1 车辆

- 车型与数量：公交车 ×2、小汽车 ×4（红 / 蓝 / 黄 / 白）、出租车 ×1、校车 ×1、救护车 ×1、消防车 ×1、卡车 ×1、自行车 ×3、停放的滑板车 ×1、河上小船 ×1。
- 行驶路径：沿主街、学校街、公园路和北环路组成的闭合样条循环（CatmullRomCurve3，closed=true）；每辆车有固定初始偏移，保证每次打开布局一致。
- 速度：6–10 m/s（视觉速度，不追求物理真实）；转弯时车身朝速度方向平滑旋转。
- 路口行为：接近红灯时在停止线前平滑减速并停住；绿灯亮起后 0.5s 再起步；黄灯时已过线的车继续通过。
- 公交站行为：公交车到站后停靠 4 秒，车门（简化为一块可旋转的面板）打开再关闭，然后继续行驶。
- 校车沿学校街慢速循环，在学校门口停靠 3 秒。
- 救护车 / 消防车车顶灯用 emissive 做红蓝 / 红红交替脉冲闪烁。
- 自行车在绿色自行车道上行驶，速度 3 m/s，骑手做简单踩踏摆腿动画。
- 小船在河面上沿短样条来回缓慢移动，船身轻微上下浮动。
- 点击行驶中的车辆时，该车暂停 1.5 秒并弹出单词卡；关闭卡片后恢复行驶。停放的车辆 / 滑板车正常可点。

### 4.2 行人

- 数量：12 个左右，低多边形小人（2.5 头身，圆头 + 胶囊身体 + 摆臂摆腿）。
- 类型：上班族、学生、推婴儿车的家长、遛狗的人、快递员、校门口的值日警察（police officer）、公园里放风筝的孩子。
- 行为：沿人行道样条行走，速度 1.1–1.4 m/s，身体轻微上下起伏 + 手臂摆动；到斑马线前等待行人绿灯，绿灯后结伴过街；在公交站、公园长椅、学校门口有 3–6 秒的停留。
- 行人过街时车辆必须让行（车辆在停止线前停住）。
- 遛狗的人身边跟一只小狗，小狗有摇尾巴和短距离跑动。

### 4.3 红绿灯

- 两个信号灯路口：学校街 × 主街 `(-10, 0)`、公园路 × 主街 `(35, 0)`。
- 每个路口四角各有车行灯 + 人行灯；灯杆为深灰，灯箱为黑色，红 / 黄 / 绿三色灯珠带自发光和光晕。
- 周期 25 秒：车行绿灯 12s → 黄灯 3s → 红灯 10s；人行灯与车行灯反向，绿灯最后 3 秒闪烁。
- 两个路口相位错开 7 秒，避免全城同时红 / 绿。
- 学校门口 `x ≈ 6` 的斑马线由值日警察举牌指挥：红灯时警察站在路中举起「STOP」牌，车辆停止；绿灯时退回人行道。这个路口不使用电子灯，增加真实感。
- 车辆、行人、灯色必须严格联动：红灯停、绿灯行，不能出现车流穿过红灯或行人被车穿模。

### 4.4 环境动画

- 喷泉：三层水柱 + 水花粒子（可用少量 sprite / 低多边形小球），循环起落。
- 树木：树冠做幅度很小的顶点摆动或整体轻微摇摆（不同树相位错开）。
- 风筝：在公园上空按 8 字形缓慢飘动，线连到地面孩子的手。
- 鸭子：在池塘里绕小圈游动，偶尔低头。
- 云朵：天空 5–6 朵低多边形云缓慢横向漂移，到边界循环。
- 飞鸟：远处 4 只小鸟绕大圈飞行。
- 旗帜 / 遮阳篷 / 横幅：轻微飘动（可用顶点动画或整体小幅旋转）。
- 所有动画使用同一个 `Clock` 和 `delta`，`delta` 上限 0.05s，防止切后台回来时跳帧。

---

## 5. 50 个可点击单词（唯一数据源）

### 5.1 数据规则

- 每个单词对象必须有稳定、蛇形命名的 `id`，**50 个 id 一个都不能改、不能少、不能重复**。
- 每个对象包含：`id`、`word`、`phonetic`、`zh`、`kidDefinition`、`example`、`category`、`zone`。
- `category` 只能是 6 个值：`places` / `transport` / `street` / `people` / `nature` / `animals`。
- `zone` 只能是 5 个值：`main_street` / `school_zone` / `hospital_zone` / `park_zone` / `citywide`。
- 单词卡、词汇表、进度点阵、英文标签都必须从这一份数据渲染，禁止把单词文案硬编码在 UI 里。
- 英文例句保持 3–7 个词，只使用该年龄段能懂的词。

### 5.2 完整词表（共 50 个）

| id | 英文 | 音标 | 中文 | 儿童解释 | 例句 | 分类 | 区域 |
|----|------|------|------|----------|------|------|------|
| hospital | hospital | /ˈhɑːspɪtl/ | 医院 | 生病时去看医生的地方。 | I go to the hospital when I am sick. | places | hospital_zone |
| school | school | /skuːl/ | 学校 | 小朋友上课和玩耍的地方。 | I learn ABC at school. | places | school_zone |
| park | park | /pɑːrk/ | 公园 | 有大树和草地，可以散步玩的地方。 | We play in the park. | places | park_zone |
| supermarket | supermarket | /ˈsuːpərmɑːrkɪt/ | 超市 | 可以买到食物和日用品的大商店。 | Mom buys milk at the supermarket. | places | main_street |
| bus_stop | bus stop | /ˈbʌs stɑːp/ | 公交站 | 等公交车的地方。 | We wait at the bus stop. | places | main_street |
| police_station | police station | /pəˈliːs ˈsteɪʃən/ | 警察局 | 警察叔叔工作的地方。 | The police officer works at the police station. | places | main_street |
| fire_station | fire station | /ˈfaɪər ˈsteɪʃən/ | 消防站 | 消防员和消防车住的地方。 | The fire truck lives at the fire station. | places | hospital_zone |
| library | library | /ˈlaɪbreri/ | 图书馆 | 可以安静看书、借书的地方。 | I read books at the library. | places | school_zone |
| bakery | bakery | /ˈbeɪkəri/ | 面包店 | 烤面包和蛋糕的香香小店。 | The bakery smells sweet. | places | main_street |
| cafe | cafe | /kæˈfeɪ/ | 咖啡馆 | 可以坐下来喝东西的地方。 | We drink juice at the cafe. | places | main_street |
| post_office | post office | /ˈpoʊst ˌɔːfɪs/ | 邮局 | 寄信和包裹的地方。 | I send a letter at the post office. | places | main_street |
| cinema | cinema | /ˈsɪnəmə/ | 电影院 | 看大银幕电影的地方。 | We watch a movie at the cinema. | places | main_street |
| bus | bus | /bʌs/ | 公交车 | 载很多人一起走的车。 | The bus takes us to school. | transport | main_street |
| car | car | /kɑːr/ | 小汽车 | 爸爸开的小汽车。 | The car is red. | transport | main_street |
| taxi | taxi | /ˈtæksi/ | 出租车 | 招手就停、送你去目的地的车。 | We take a taxi to the station. | transport | main_street |
| bicycle | bicycle | /ˈbaɪsɪkl/ | 自行车 | 用脚踩的两轮车。 | I ride my bicycle. | transport | school_zone |
| ambulance | ambulance | /ˈæmbjələns/ | 救护车 | 送病人去医院的白色车。 | The ambulance goes to the hospital. | transport | hospital_zone |
| fire_truck | fire truck | /ˈfaɪər trʌk/ | 消防车 | 消防员灭火开的红色大车。 | The fire truck is red. | transport | hospital_zone |
| school_bus | school bus | /skuːl bʌs/ | 校车 | 接送小朋友上学的黄色车。 | The school bus picks up the children. | transport | school_zone |
| truck | truck | /trʌk/ | 卡车 | 装很多货物的大车。 | The truck carries boxes. | transport | main_street |
| scooter | scooter | /ˈskuːtər/ | 滑板车 | 一只脚踩、一只脚蹬的小车。 | I ride my scooter in the park. | transport | park_zone |
| boat | boat | /boʊt/ | 小船 | 在水上开的船。 | The boat sails on the river. | transport | park_zone |
| road | road | /roʊd/ | 马路 | 汽车和行人走的马路。 | Cars drive on the road. | street | citywide |
| crosswalk | crosswalk | /ˈkrɔːswɔːk/ | 斑马线 | 过马路时走的白色条纹。 | Walk on the crosswalk. | street | school_zone |
| traffic_light | traffic light | /ˈtræfɪk laɪt/ | 红绿灯 | 红黄绿三色灯，指挥车和行人。 | The traffic light is green. | street | school_zone |
| streetlight | streetlight | /ˈstriːtlaɪt/ | 路灯 | 晚上照亮马路的灯。 | The streetlight helps us see at night. | street | main_street |
| bench | bench | /bentʃ/ | 长椅 | 公园里可以坐下休息的长椅。 | We sit on the bench. | street | park_zone |
| trash_can | trash can | /træʃ kæn/ | 垃圾桶 | 扔垃圾的地方。 | Put the paper in the trash can. | street | main_street |
| mailbox | mailbox | /ˈmeɪlbɑːks/ | 邮筒 | 把信投进去的箱子。 | I put a letter in the mailbox. | street | main_street |
| bridge | bridge | /brɪdʒ/ | 小桥 | 架在河上，可以走过去。 | We walk across the bridge. | street | park_zone |
| fountain | fountain | /ˈfaʊntn/ | 喷泉 | 会喷水的小水池。 | Water comes out of the fountain. | street | main_street |
| teacher | teacher | /ˈtiːtʃər/ | 老师 | 教小朋友学习的人。 | My teacher is kind. | people | school_zone |
| doctor | doctor | /ˈdɑːktər/ | 医生 | 帮病人看病的人。 | The doctor helps sick people. | people | hospital_zone |
| nurse | nurse | /nɜːrs/ | 护士 | 在医院照顾病人的人。 | The nurse is very kind. | people | hospital_zone |
| police_officer | police officer | /pəˈliːs ˈɔːfɪsər/ | 警察 | 保护大家安全的警察。 | The police officer helps us. | people | main_street |
| firefighter | firefighter | /ˈfaɪərfaɪtər/ | 消防员 | 灭火救人的消防员。 | The firefighter is brave. | people | hospital_zone |
| driver | driver | /ˈdraɪvər/ | 司机 | 开车的人。 | The bus driver says hello. | people | main_street |
| baker | baker | /ˈbeɪkər/ | 面包师 | 做面包和蛋糕的人。 | The baker makes bread. | people | main_street |
| student | student | /ˈstuːdnt/ | 学生 | 在学校学习的小朋友。 | I am a student. | people | school_zone |
| tree | tree | /triː/ | 树 | 有树干、树枝和叶子的大植物。 | The tree is tall. | nature | park_zone |
| flower | flower | /ˈflaʊər/ | 花 | 有花瓣、香香的小植物。 | The flower is pink. | nature | park_zone |
| grass | grass | /ɡræs/ | 草地 | 地上绿绿的矮矮的植物。 | The grass is green. | nature | park_zone |
| pond | pond | /pɑːnd/ | 池塘 | 公园里的小水池。 | Ducks swim in the pond. | nature | park_zone |
| swing | swing | /swɪŋ/ | 秋千 | 荡来荡去的秋千。 | I swing high on the swing. | nature | park_zone |
| slide | slide | /slaɪd/ | 滑梯 | 从上面滑下来的滑梯。 | I slide down the slide. | nature | park_zone |
| seesaw | seesaw | /ˈsiːsɔː/ | 跷跷板 | 一上一下的跷跷板。 | We play on the seesaw. | nature | park_zone |
| kite | kite | /kaɪt/ | 风筝 | 用线拉着飞上天的玩具。 | The kite flies in the sky. | nature | park_zone |
| duck | duck | /dʌk/ | 鸭子 | 会游泳、嘎嘎叫的小动物。 | The duck says quack. | animals | park_zone |
| dog | dog | /dɔːɡ/ | 小狗 | 会汪汪叫、爱摇尾巴的小动物。 | The dog runs fast. | animals | park_zone |
| bird | bird | /bɜːrd/ | 小鸟 | 有翅膀、会飞的小动物。 | The bird sings in the tree. | animals | citywide |

### 5.3 单词对象与 3D 物体对应

- 每个 id 必须对应场景里一个**明确可辨**的 3D 物体，而不是只放一个隐形热区。
- 建筑类单词（医院、学校等）点击整栋建筑或主门口；车辆类点击车身；人物类点击人物；自然类点击树 / 花 / 秋千等实体。
- `traffic_light` 点击任意一个路口的灯杆；`road` 点击主街路面；`crosswalk` 点击学校门口斑马线；`bird` 点击空中飞鸟；`kite` 点击风筝。
- 同一类物体有多个实例时（树、花、长椅、路灯），只在「主实例」上挂单词，其他实例作为装饰；主实例要放在镜头容易看到的位置，并略大一点。
- 点击后该物体要有 1.2 秒的「呼吸高亮」：外轮廓描边或 emissive 脉冲 + 轻微放大；同时镜头平滑聚焦到它，保持 3/4 视角，不要进入物体内部。

---

## 6. 交互与 UI

### 6.1 页面结构

桌面 / 横屏：

```
┌─────────────────────────────────────────────────────────────┐
│ 小词城 WORD CITY         5 个区域 · 50 个单词   [词汇表]     │
├──────────────────────────────────────────┬──────────────────┤
│  分区标签：全城 商业街 学校 公园 医院       │  学习面板         │
│                                          │  ┌────────────┐  │
│           3D 城市画布                     │  │ 单词卡      │  │
│      （旋转 / 缩放 / 平移）                │  │ 英文 / 音标 │  │
│                                          │  │ 中文 / 解释 │  │
│  [显示英文标签]              [重置视角]    │  │ 例句 / 发音 │  │
│                                          │  └────────────┘  │
│                                          │  进度点阵 0/50    │
└──────────────────────────────────────────┴──────────────────┘
```

手机竖屏：

- 3D 画布占满上半屏；
- 分区标签横向可滚动；
- 单词卡从底部滑出为 bottom sheet（带拖拽手柄），默认露出 35%，上滑展开；
- 词汇表为全屏 modal；
- 所有触控目标 ≥ 44×44px，注意 `env(safe-area-inset-*)`。

### 6.2 分区镜头（5 个标签）

| 标签 | id | 镜头目标 | 说明 |
|------|----|----------|------|
| 全城 | overview | 俯视 3/4 全景，看得到四个街区和河流 | 默认视图 |
| 商业街 | main_street | 主街西段 + 中央广场 + 公交站 | 超市 / 面包店 / 咖啡馆 / 邮局 / 电影院 |
| 学校 | school_zone | 学校 + 图书馆 + 校门斑马线 | 上学时段氛围 |
| 公园 | park_zone | 公园 + 池塘 + 游乐场 + 小桥 | 鸭子 / 风筝 / 小船 |
| 医院 | hospital_zone | 医院 + 消防站 + 救护车 | 安静、整洁的街区 |

切换标签时相机用 900ms 的缓动飞行（easeInOutCubic）移动到目标，期间禁止拖拽；结束后恢复自由环绕。

### 6.3 环绕控制

- 单指拖拽 / 鼠标左键：环绕旋转；水平 360°，垂直限制 15°–75°，不能钻到地面以下。
- 滚轮 / 双指捏合：缩放，距离 22–150m。
- 双指拖动 / 右键拖动：平移，目标点限制在地图范围内。
- 拖拽超过 6px 才算旋转，避免点击时误触。
- 点击空白处：关闭单词卡，取消高亮。
- 双击空白处：回到当前分区的默认镜头。
- 「重置视角」按钮：回到当前分区默认镜头。

### 6.4 单词卡

打开单词卡时，从场景数据读取：

```
[分类 chip]  12 / 50
hospital
/ˈhɑːspɪtl/
医院
🏥 生病时去看医生的地方。
I go to the hospital when I am sick.
[🔊 听发音]   [← 上一个] [下一个 →]
```

- 顶部大号英文单词（28–34px，圆润字体），下方音标（次级色）。
- 中文与儿童解释分层显示，解释前可放一个与分类对应的小图标。
- 例句用斜体或浅色底，英文句子可点击整句朗读。
- 「听发音」按钮：点击朗读英文单词；打开卡片时自动朗读一次（可在设置中关闭）。
- 上一个 / 下一个：按当前分区内的单词顺序循环，同时镜头飞向下一个对象。
- 关闭按钮 + `Esc` + 点击空白处都能关闭。
- 已探索过的单词在卡片和词汇表里显示一个绿色小勾。

### 6.5 英文标签

- 默认关闭（移动端）/ 开启（桌面端宽度 ≥ 900px）。
- 开启后，每个已探索或当前可见的对象上方显示英文名，带一条细引线连到物体；标签用半透明白底 + 圆角 + 轻阴影。
- 标签之间做避让：重叠时优先显示当前高亮 / 已探索 / 距离镜头近的对象，其余隐藏。
- 标签不遮挡红绿灯、车辆和人物脸部。
- 切换开关时 200ms 淡入淡出。

### 6.6 词汇表

- 全屏 / 大 modal，标题「小词城词汇表」，顶部显示 `已收集 X / 50`。
- 按 6 个分类分组：地点 / 交通 / 街道 / 人物 / 自然 / 动物；每组有彩色分组标题和数量。
- 每个词条显示英文、中文、小发音按钮、已收集勾选；点击词条 → 关闭词汇表 → 镜头飞到该对象 → 打开单词卡。
- 提供搜索框（英文 / 中文模糊匹配），空结果有友好提示。
- 桌面端支持键盘上下选择、Enter 打开、Esc 关闭；modal 内焦点陷阱。

### 6.7 进度与完成

- 右下 / 侧栏固定显示进度点阵：50 个小圆点，按分类着色，已探索点亮。
- 每点开一个新单词，对应圆点做 300ms 弹跳 + 粒子小星星（不授星，仅视觉）。
- 收集到 50/50：全屏撒纸屑 2 秒 + 面板显示「小词城探索家」徽章，文案「你认识了小词城里的 50 个单词！」；不弹分数、不弹评价、不要求分享。
- 进度写入 `localStorage('wordcity.discovered.v1')`，刷新后恢复；同时通过桥接上报给原生。

### 6.8 新手引导

首次打开（localStorage 无记录）显示 3 步轻提示：

1. 「拖动旋转，双指缩放」；
2. 「点一点建筑、车子和小动物」；
3. 「打开词汇表，看看 50 个单词」。

点「知道啦」逐条消失，不遮挡主要操作；后续不再出现。

### 6.9 错误与空状态

- 加载中：画布中央显示低多边形城市剪影 + 旋转小圆点 + 「正在搭建小词城…」。
- WebGL 不可用 / 初始化失败：显示友好错误卡，说明可以打开词汇表看全部单词；提供「重新加载」按钮。
- 某个 id 找不到对应物体：控制台警告，词汇表仍可打开该词，不崩溃。
- 无网络：全部资源本地化，不出现任何网络请求失败提示。

---

## 7. 视觉风格

### 7.1 整体气质

低多边形、等距微缩模型感、明亮但不刺眼；像一套摆在桌上的木质城市玩具。圆角、厚实、颜色分区清晰；避免写实纹理、避免霓虹赛博、避免过度饱和。

### 7.2 色板

| 用途 | 颜色 |
|------|------|
| 天空渐变 | `#CDEFFB` → `#F4FBF7` |
| 草地 | `#7ECB6A` / 深色 `#5FAE54` |
| 道路 | `#4B5563`，车道线 `#F8F5EA`，自行车道 `#8FD3A8` |
| 人行道 | `#E4DCCB`，路缘 `#C9BFAE` |
| 建筑主色 | 珊瑚 `#F2826A`、芥末 `#F2C14E`、薄荷 `#6FCF97`、天蓝 `#6FA8DC`、薰衣草 `#A78BFA`、奶油 `#FFF3D6` |
| 屋顶 | 同色系加深 15%–25% |
| 红绿灯 | 红 `#E5484D`、黄 `#F5A524`、绿 `#30A46C` |
| 品牌强调色 | `#FF9F43`（与小星老师一致） |
| 文字 | 主 `#2D2A26`，次 `#746E64`，弱 `#A39C90` |
| 卡片背景 | `#FFFDF8`，边框 `#E8E1D4` |

每个街区分一个主色系：学校区奶油 + 珊瑚、医院区薄荷 + 白、商业街芥末 + 珊瑚、公园区绿色 + 天蓝；但整体要保持统一，不要变成四个互不相关的世界。

### 7.3 建模风格

- 建筑：圆角立方体（用 BoxGeometry 或 RoundedBox 简化），墙面纯色，窗户用深色内嵌面片 + 白色窗框；每栋建筑至少 3 个可识别细节（招牌、雨棚、门、窗、屋顶水箱、烟囱、旗帜）。
- 车辆：低多边形车体 + 圆柱车轮 + 深色车窗；公交车和校车要有明显车头、车门、车顶；出租车有顶灯；救护车有红十字；消防车有梯子和警灯。
- 人物：2.5 头身，圆头 + 胶囊身体 + 圆柱四肢；不同职业靠颜色和帽子区分（医生白大褂、护士帽、警察帽、消防员头盔、面包师围裙、学生书包）。
- 自然：树 = 圆柱树干 + 2–3 个二十面体 / 圆锥树冠；花 = 细茎 + 五瓣；鸭子 = 椭圆身体 + 小头 + 橙嘴；狗 = 低多边形身体 + 尾巴。
- 水面：半透明蓝色平面 + 顶点轻微波动或两层错位波纹面片。
- 阴影：暖灰色柔和阴影；大建筑和车辆投射真实阴影，小物件用圆形渐变贴片做假阴影，控制性能。

### 7.4 光照

- 一盏方向光（暖白 `#FFF4E0`，强度 1.1）从右上方照射，开阴影，阴影贴图 2048。
- 一盏半球光 / 环境光补亮暗部（天空色 `#DDF3FF`，地面色 `#F0E6D2`，强度 0.8）。
- 不使用后处理（Bloom 等）以保证移动端性能；红绿灯和警示灯的光晕用 sprite / 半透明面片模拟。
- 固定「晴朗下午」光照，不做昼夜循环。

### 7.5 UI 风格

- 字体：系统字体栈（`-apple-system, "PingFang SC", "HarmonyOS Sans SC", "Noto Sans SC", sans-serif`），不加载网络字体；英文标题可用圆润字重 700。
- 圆角：卡片 16–20px，按钮 12–14px，标签 999px。
- 阴影柔和，边框 1px 暖灰；不使用纯黑。
- 图标用内联 SVG（线性、1.8px 描边、圆角端点），不引入图标库。
- 动效克制：hover 抬升 1px、按下缩放 0.97、面板滑入 240ms。

---

## 8. 技术约束（必须遵守）

### 8.1 运行环境

- 运行在 HarmonyOS ArkWeb（Chromium 内核）的 Web 容器中，通过 `resource://rawfile/city3d/index.html` 加载。
- 页面内资源用相对路径（`./assets/...`），由 ArkWeb 同源解析；**不能**使用 `file://`、`http://`、CDN 或任何网络请求。
- 使用本地 `assets/vendor/three.min.js`（r0.185，全局 `THREE`），用普通 `<script>` 标签加载，**不使用 ES Module / import / npm / 构建步骤**。
- 不使用 `speechSynthesis`（ArkWeb 不支持），发音通过宿主桥接；在桌面浏览器预览时可用 `speechSynthesis` 兜底。
- 所有贴图用 `CanvasTexture` 程序化生成（招牌文字、路面箭头、公交时刻表等），不加载图片文件。

### 8.2 文件结构（与 room3d 同构）

```
city3d/
├── index.html
└── assets/
    ├── city.css            # 布局、面板、响应式
    ├── city-panel.css      # 单词卡、词汇表、进度
    ├── city-dialogs.css    # modal、toast、加载 / 错误态
    ├── city-host.css       # 鸿蒙宿主模式（隐藏顶部品牌栏等）
    ├── city-data.js        # 50 个单词 + 区域 + 镜头 + 交通配置（唯一数据源）
    ├── city-models.js      # 所有低多边形建模函数（建筑 / 车辆 / 人物 / 自然）
    ├── city-scene.js       # 渲染器、相机、光照、道路、交通系统、动画循环
    ├── city-app.js         # UI 状态、单词卡、词汇表、进度、桥接
    └── vendor/
        └── three.min.js    # 本地 three.js r0.185
```

- `city-data.js` 暴露 `window.WordCityData = { objects, zones, views, traffic }`。
- `city-models.js` 暴露 `window.WordCityModels = { buildCity, buildVehicle, buildPerson, ... }`。
- `city-scene.js` 暴露 `window.WordCityScene = { init, setView, focusObject, setPaused, ... }`。
- `city-app.js` 暴露 `window.WordCityApp`（见 8.3），并在 DOM 就绪后启动。
- 代码注释使用中文，命名使用英文；不要压缩、不要混淆，方便后续原生侧维护。

### 8.3 宿主桥接 API（与 room3d 同构，前缀改为 City）

Web 侧读取由 ArkWeb `javaScriptProxy` 注入的 `window.CityNativeBridge`：

| 方法 | 方向 | 说明 |
|------|------|------|
| `speak(word, zh)` | Web → 原生 | 朗读英文单词；返回字符串 `"true"` / `"false"` |
| `stopSpeak()` | Web → 原生 | 停止朗读 |
| `onReady()` | Web → 原生 | 3D 场景首帧渲染完成 |
| `onSelect(id, word)` | Web → 原生 | 用户点开某个单词 |
| `onProgress(idsJson)` | Web → 原生 | 已探索 id 的 JSON 数组变化 |

原生侧通过 `runJavaScript` 调用：

```js
window.WordCityApp.select(id)      // 高亮并打开单词
window.WordCityApp.setLabels(bool) // 显示 / 隐藏英文标签
window.WordCityApp.setView(viewId)// overview / main_street / school_zone / park_zone / hospital_zone
window.WordCityApp.ids()           // 返回 50 个 id
```

- 所有桥接调用必须做存在性判断（`window.CityNativeBridge && ...`），浏览器预览时静默降级。
- 点击对象后先播放本地高亮，再调用 `onSelect`；不要等待原生返回。
- 进度变化时防抖 200ms 再上报，避免频繁调用。

### 8.4 性能预算

- 目标：中端手机 55–60fps；三角形总数 ≤ 120k；绘制调用 ≤ 80。
- 共享几何体和材质：所有树、路灯、花、栅栏柱、车轮等重复物体用 `InstancedMesh` 或共享 geometry + material。
- 静态建筑按材质合并（`BufferGeometryUtils.mergeGeometries` 若可用，否则按 material 分组）。
- 阴影只给大建筑、车辆、人物开启；小物件用假阴影贴片。
- 渲染器 `antialias: true`，`pixelRatio = Math.min(devicePixelRatio, 2)`。
- 页面 `visibilitychange` 隐藏时暂停动画和渲染；重新可见时恢复。
- 文本标签不要每帧重建 DOM；只在相机移动结束后更新位置，或使用 30fps 节流。
- 不使用大量透明面片叠加；粒子总数 ≤ 200。

---

## 9. 无障碍与儿童可用性

- 所有按钮有 `aria-label`；单词卡使用 `role="dialog"` + `aria-modal`，打开时焦点进入卡片，关闭后焦点回到触发元素。
- 支持键盘：`Tab` 遍历、`Enter` 打开、`Esc` 关闭、方向键在词汇表中移动。
- 场景提供一段屏幕阅读器描述（`sr-only`），说明城市分区、50 个单词和基本操作。
- 颜色不是唯一信息通道：红绿灯同时用位置（红上绿下）和亮度区分；分类同时用图标 + 文字。
- 所有文字对比度 ≥ 4.5:1；正文 ≥ 14px，儿童主要按钮 ≥ 16px。
- 尊重 `prefers-reduced-motion`：关闭相机飞行缓动（改为直接切换）、关闭树木摇摆和云朵漂移、保留红绿灯逻辑。
- 不出现闪烁频率 > 3Hz 的强光；警灯脉冲要柔和。
- 不收集任何个人数据，不做分享、排行、内购或外链。

---

## 10. 优先级（如果实现时间有限）

**P0（必须完成）**

1. 3D 城市场景 + 四个街区 + 主街 + 河流 + 中央广场；
2. 50 个可点击对象，全部能打开正确的单词卡；
3. 环绕 / 缩放 / 平移 + 5 个分区镜头；
4. 单词卡、词汇表、进度点阵、英文标签开关；
5. 红绿灯循环 + 车辆沿路行驶 + 行人在人行道行走；
6. 移动端响应式 + 离线资源。

**P1（体验加分）**

7. 车辆遇红灯停车、公交到站停靠、行人过街；
8. 点击移动车辆暂停 + 镜头聚焦；
9. TTS 桥接、进度持久化、首次引导；
10. 喷泉 / 鸭子 / 风筝 / 云朵等环境动画。

**P2（有余力再做）**

11. 警灯脉冲、校门口值日警察举牌；
12. 收集完成纸屑 + 「小词城探索家」徽章；
13. 词汇表搜索、键盘完整支持；
14. 假阴影、材质细节、广告牌和店铺招牌的个性化。

---

## 11. 验收清单

- [ ] 打开页面 3 秒内看到完整城市，无空白、无控制台报错。
- [ ] 全城 / 商业街 / 学校 / 公园 / 医院 5 个标签都能平滑切换镜头。
- [ ] 50 个 id 与词表完全一致，每个都能点击并打开正确单词卡。
- [ ] 单词卡的英文、音标、中文、儿童解释、例句与词表逐字一致。
- [ ] 打开单词卡自动朗读；「听发音」可重复朗读；浏览器预览有兜底发音。
- [ ] 英文标签开关有效，标签不重叠、不遮挡关键物体。
- [ ] 词汇表按 6 类分组，显示 50 个词与收集状态，点击可定位到场景。
- [ ] 进度点阵 50 格，刷新后从 localStorage 恢复；50/50 有完成庆祝。
- [ ] 两个路口红绿灯按 25s 周期循环，车辆红灯停、绿灯行。
- [ ] 公交车在公交站停靠，校车在学校门口停靠。
- [ ] 行人沿人行道行走，绿灯过斑马线，车辆让行。
- [ ] 点击行驶中的车辆会暂停并打开单词卡，关闭后恢复。
- [ ] 场景中至少有 8 种非单词装饰（消防栓、交通锥、井盖、广告牌、遮阳篷、屋顶水箱、花坛、护栏等）。
- [ ] 移动端竖屏单词卡为底部 sheet，触控目标 ≥ 44px，无横向滚动。
- [ ] 页面无任何网络请求；断网可完整使用。
- [ ] 中端手机 3D 交互流畅，无明显掉帧；切后台再回来不跳帧。
- [ ] WebGL 失败时有友好错误态和词汇表兜底。
- [ ] 代码为未压缩的普通 script，文件结构与第 8.2 节一致。

---

## 12. 输出要求

1. 先用不超过 15 行说明你的设计取舍（分区、镜头、性能）。
2. 然后按第 8.2 节的文件结构，**逐个输出完整文件内容**（`index.html`、5 个 CSS、4 个 JS；`vendor/three.min.js` 视为已存在，不需要输出）。
3. 不要省略任何单词数据或建模函数；不要用 `// ...` 省略代码。
4. 不要引入外部依赖、字体、图片或 CDN。
5. 如果某个细节无法确定，选择对儿童更友好、对性能更安全的方案，并在代码注释里说明。
6. 最终产物应能直接放进 `entry/src/main/resources/rawfile/city3d/` 并在 HarmonyOS Web 容器中打开。
