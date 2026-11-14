// TTS 引擎 provider key 查找纯函数 (零依赖, 便于单测)
// 云 TTS 引擎复用对应服务商配置的 API Key; 只接受 id 匹配且 apiKey 非空的条目。

export interface TtsProviderKeyRef {
  id: string
  apiKey: string
}

// 返回匹配 provider 的 apiKey; 未配置返回空串
export function findProviderApiKey(providers: TtsProviderKeyRef[], providerId: string): string {
  const matched = providers.find((p) => p.id === providerId && p.apiKey !== '')
  return matched === undefined ? '' : matched.apiKey
}
