import { ApiStyle } from '../../models/ChatModels'

// ============ 公开 enum / interface(对外契约,从旧 ProviderCompatibilityRegistry 平移) ============

export interface CompatibilityProviderInfo {
  providerId: string
  baseUrl: string
  apiStyle: ApiStyle
}

export enum ModelDiscoveryStrategy {
  REMOTE_ENDPOINT = 'remote_endpoint',
  STATIC_CATALOG = 'static_catalog'
}

export enum AnthropicAuthStrategy {
  API_KEY = 'api_key',
  BEARER = 'bearer'
}

export enum OpenAIStreamContentMode {
  INCREMENTAL = 'incremental',
  CUMULATIVE = 'cumulative'
}

export enum ReasoningControlMode {
  NONE = 'none',
  TOGGLE = 'toggle',
  EFFORT = 'effort',
  HIGH_MAX = 'high_max'
}

export enum ReasoningRequestStrategy {
  NONE = 'none',
  OPENAI_REASONING_EFFORT = 'openai_reasoning_effort',
  OPENAI_COMPAT_REASONING_EFFORT = 'openai_compat_reasoning_effort',
  OPENAI_REASONING_SPLIT = 'openai_reasoning_split',
  OPENROUTER_REASONING = 'openrouter_reasoning',
  ANTHROPIC_THINKING = 'anthropic_thinking',
  DEEPSEEK_THINKING = 'deepseek_thinking',
  MIMO_THINKING = 'mimo_thinking',
  ZHIPU_THINKING = 'zhipu_thinking',
  DASHSCOPE_THINKING = 'dashscope_thinking',
  KIMI_THINKING = 'kimi_thinking',
  GOOGLE_THINKING_CONFIG = 'google_thinking_config',
  SILICONFLOW_THINKING = 'siliconflow_thinking'
}

export interface ProviderCompatibilityProfile {
  modelDiscoveryStrategy: ModelDiscoveryStrategy
  staticModels: string[]
  defaultTestModel: string
  anthropicAuthStrategy: AnthropicAuthStrategy
  anthropicBearerRetryOnAuthFailure: boolean
  openAIStreamContentMode: OpenAIStreamContentMode
  preserveAssistantReasoningDetails: boolean
  reasoningControlMode: ReasoningControlMode
  defaultReasoningRequestStrategy: ReasoningRequestStrategy
  // OpenAI Responses API 是否支持通过 include 透传 reasoning.encrypted_content
  // 用于在多轮对话里保持推理状态(gpt-5 / o-系列官方 Responses 支持)
  // 非官方代理默认关闭,避免 include 字段触发 HTTP 400
  supportsOpenAIResponsesEncryptedReasoning: boolean
}

export const DEFAULT_PROFILE: ProviderCompatibilityProfile = {
  modelDiscoveryStrategy: ModelDiscoveryStrategy.REMOTE_ENDPOINT,
  staticModels: [],
  defaultTestModel: '',
  anthropicAuthStrategy: AnthropicAuthStrategy.API_KEY,
  anthropicBearerRetryOnAuthFailure: false,
  openAIStreamContentMode: OpenAIStreamContentMode.INCREMENTAL,
  preserveAssistantReasoningDetails: false,
  reasoningControlMode: ReasoningControlMode.NONE,
  defaultReasoningRequestStrategy: ReasoningRequestStrategy.NONE,
  supportsOpenAIResponsesEncryptedReasoning: false
}

export const MINIMAX_COMPATIBLE_MODELS: string[] = [
  'MiniMax-M3',
  'MiniMax-M2.5',
  'MiniMax-M2.5-highspeed',
  'MiniMax-M2.1',
  'MiniMax-M2.1-highspeed',
  'MiniMax-M2'
]

// ============ DSL 数据结构 ============

// Provider 命中条件:同一 spec 内 3 个字段 OR(任一命中即整 spec 命中)
export interface ProviderMatchSpec {
  providerIds?: string[]          // providerId 严格相等(任一)
  baseUrlIncludesAny?: string[]   // baseUrl 子串(任一)
  baseUrlEqualsAny?: string[]     // baseUrl 规范化后严格相等(任一)
}

// Provider 配置定义:apiStyle 必须匹配,match 内含 OR
export interface ProviderProfileDef {
  id: string                                       // 仅诊断/日志用
  apiStyle: ApiStyle                               // 强制匹配
  match: ProviderMatchSpec                         // 命中条件
  profile: Partial<ProviderCompatibilityProfile>   // 与 DEFAULT_PROFILE 合并
}

// 仅 apiStyle 匹配的兜底定义(catch-all,放在列表末尾)
export interface ProviderProfileFallback {
  id: string
  apiStyle: ApiStyle
  profile: Partial<ProviderCompatibilityProfile>
}

// Model 命中条件:同一 def 内多个 spec AND(全部命中)
export interface ModelMatchSpec {
  tokens?: string[]      // tokenize 后顺序子序列命中(允许 token 间间隔)
  notTokens?: string[]   // 顺序子序列 *不* 命中
  exactId?: string       // modelId 与本字段(不区分大小写)完全相等
  startsWith?: string    // modelId 不区分大小写的字符串前缀(对路径式 id 友好,等价旧 startsWith)
}

// Model 级模型能力定义
export interface ModelProfileDef {
  id: string                // 诊断用
  match: ModelMatchSpec[]   // AND
}
