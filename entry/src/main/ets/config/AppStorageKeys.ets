// AppStorage 键名统一定义，避免跨模块字符串散落
export class AppStorageKeys {
  // 事件通知类键
  static readonly OPEN_NEW_CHAT: string = 'openNewChat'
  static readonly OPEN_NEW_CHAT_WITH_PROMPT: string = 'openNewChatWithPrompt'
  static readonly OPEN_SESSION_PAYLOAD: string = 'openSessionPayload'
  static readonly OPEN_IMAGE_GENERATION: string = 'openImageGeneration'
  static readonly SESSION_LIST_REFRESH_AT: string = 'session_list_refresh_at'
  static readonly ASSISTANT_AVATAR_REFRESH_AT: string = 'assistant_avatar_refresh_at'
  // 助手保存/创建后通知 ChatPage 重新读取 enabledToolIds / reasoningLevel 的脉冲
  static readonly ASSISTANT_RUNTIME_REFRESH_AT: string = 'assistant_runtime_refresh_at'
  static readonly SCREENSHOT_DISMISSED_TS: string = 'screenshot_dismissed_ts'
  static readonly TASK_EVENT_TICK: string = 'task_event_tick'
  static readonly IN_APP_TASK_ALERT_PAYLOAD: string = 'in_app_task_alert_payload'
  static readonly IN_APP_IMAGE_GENERATION_ALERT_PAYLOAD: string = 'in_app_image_generation_alert_payload'
  static readonly PENDING_TOOL_INTERACTION_TICK: string = 'pending_tool_interaction_tick'
  static readonly RUNNING_CHAT_TASK_COUNT: string = 'running_chat_task_count'
  static readonly ACTIVE_IMAGE_GENERATION_PAGE: string = 'active_image_generation_page'

  // 系统状态键
  static readonly APP_IN_BACKGROUND: string = 'appInBackground'
  static readonly ACTIVE_CHAT_SESSION_ID: string = 'activeChatSessionId'
  static readonly IS_DARK_MODE: string = 'isDarkMode'
  static readonly TOP_AVOID_HEIGHT: string = 'topAvoidHeight'
  static readonly BOTTOM_AVOID_HEIGHT: string = 'bottomAvoidHeight'
  static readonly SPEAKING_MESSAGE_ID: string = 'speakingMessageId'
  // 语音交互模式（ChatPage 本地 @Local isVoiceMode 的跨组件镜像）。
  // 互动卡片（如 VerticalMathCard 步进朗读）在交互时刻直接 AppStorage.get 读取，
  // 不走 observeAppUiState 监听，所以 raw setOrCreate 即可。值：1 开 / 0 关。
  static readonly VOICE_MODE_ENABLED: string = 'voice_mode_enabled'
  static readonly WINDOW_WIDTH_VP: string = 'window_width_vp'
  static readonly WINDOW_HEIGHT_VP: string = 'window_height_vp'
  static readonly LAYOUT_SIZE_CLASS: string = 'layout_size_class'
  static readonly IS_EXPANDED_LAYOUT: string = 'is_expanded_layout'
  static readonly SETTINGS_DETAIL_PRESENTATION_MODE: string = 'settings_detail_presentation_mode'
  static readonly SETTINGS_HAND_ADAPTIVE_CHANGED_AT: string = 'settings_hand_adaptive_changed_at'
  static readonly SETTING_HAND_ADAPTIVE_ENABLED: string = 'setting_hand_adaptive_enabled'
  static readonly SETTING_HAND_ADAPTIVE_NEW_CHAT: string = 'setting_hand_adaptive_new_chat'
  static readonly SETTING_HAND_ADAPTIVE_UNSUPPORTED: string = 'setting_hand_adaptive_unsupported'
  static readonly HOLDING_HAND_STATUS: string = 'holding_hand_status'
  // 儿童模式（kids mode）激活标志: Preferences kids_mode_enabled 的响应式镜像。
  // ChatPage 据此裁剪成人入口（模型选择/标题菜单）。写入必须走 setAppUiStateValue。
  static readonly KIDS_MODE_ACTIVE: string = 'kids_mode_active'

  // 主题键
  static readonly COLOR_THEME: string = 'color_theme'
  static readonly THEME_PRIMARY: string = 'theme_primary'
  static readonly THEME_PRIMARY_LIGHT: string = 'theme_primary_light'
  static readonly THEME_BACKGROUND: string = 'theme_background'
  static readonly THEME_SURFACE: string = 'theme_surface'
  static readonly THEME_DIVIDER: string = 'theme_divider'
  static readonly THEME_USER_BUBBLE: string = 'theme_user_bubble'
  static readonly THEME_USER_BUBBLE_TEXT: string = 'theme_user_bubble_text'
  static readonly THEME_AI_BUBBLE: string = 'theme_ai_bubble'
  static readonly THEME_TEXT_PRIMARY: string = 'theme_text_primary'
  static readonly THEME_TEXT_SECONDARY: string = 'theme_text_secondary'
  static readonly THEME_TEXT_TERTIARY: string = 'theme_text_tertiary'
  static readonly THEME_MARKDOWN_TITLE: string = 'theme_markdown_title'
  static readonly THEME_MARKDOWN_TEXT: string = 'theme_markdown_text'
  static readonly THEME_MARKDOWN_LINK: string = 'theme_markdown_link'
  static readonly THEME_MARKDOWN_LINK_BG: string = 'theme_markdown_link_bg'
  static readonly THEME_MARKDOWN_CODE_BG: string = 'theme_markdown_code_bg'
  static readonly THEME_MARKDOWN_CODE_TEXT: string = 'theme_markdown_code_text'
  static readonly THEME_MARKDOWN_QUOTE_BG: string = 'theme_markdown_quote_bg'
  static readonly THEME_MARKDOWN_TABLE_BG: string = 'theme_markdown_table_bg'
  static readonly THEME_MARKDOWN_TABLE_HEADER_BG: string = 'theme_markdown_table_header_bg'
  static readonly THEME_MARKDOWN_TABLE_ALT_BG: string = 'theme_markdown_table_alt_bg'
  static readonly THEME_MARKDOWN_TABLE_BORDER: string = 'theme_markdown_table_border'

  // 聊天字体大小
  static readonly CHAT_FONT_SIZE: string = 'chat_font_size'

  // 聊天输入设置
  static readonly CHAT_INPUT_ENTER_KEY_SEND: string = 'chat_input_enter_key_send'

  // 材质效果
  static readonly MATERIAL_TYPE: string = 'material_type'
  static readonly MATERIAL_LEVEL: string = 'material_level'
  static readonly LIGHT_COLOR_MODE: string = 'light_color_mode'

  // 星星奖励系统
  static readonly STAR_EARNED_TICK: string = 'star_earned_tick'
  static readonly STAR_LAST_GRANT: string = 'star_last_grant'
  static readonly STAR_TODAY_SUMMARY: string = 'star_today_summary'
  static readonly STAR_TODAY_LOADED: string = 'star_today_loaded'

  // 每日主动招呼 (auto-greet on first open today)
  // 存储格式: 'YYYY-MM-DD' (本地时区); 空字符串 = 从未招呼过
  // 写入必须用 state/AppUiState.ets 的 setAppUiStateValue 包装,避免 AppStorageV2 陷阱
  static readonly LAST_GREET_DATE: string = 'last_greet_date'

  // 备课老师（每日动态教学）刷新通知
  // plan 更新时 pulse, ChatViewModel buildRequestSystemPrompt 检测到该值变化时重新拉取
  static readonly LESSON_PLAN_REFRESH_TICK: string = 'lesson_plan_refresh_tick'

  // 教学风格调整（评估老师每日产出）刷新通知
  // tsa 写入时 pulse, ChatViewModel buildRequestSystemPrompt 检测到该值变化时重新拉取
  static readonly TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK: string = 'teaching_style_adjustment_refresh_tick'

  // 周级趋势（评估老师每日产出）刷新通知
  // weekly_trends 写入时 pulse
  static readonly WEEKLY_TREND_REFRESH_TICK: string = 'weekly_trend_refresh_tick'
}
