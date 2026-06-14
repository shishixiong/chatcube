import { rcp } from '@kit.RemoteCommunicationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { HttpRequestController, HttpResponse } from './HttpService'

const MUSIC_GEN_CONNECT_TIMEOUT_MS = 15000
const MUSIC_GEN_TRANSFER_TIMEOUT_MS = 900000
const MUSIC_GEN_INACTIVITY_TIMEOUT_MS = 840000

// RCP 错误码
// 1007900028: Timeout was reached
// 1007900992: Request is canceled
const RCP_ERROR_TIMEOUT = 1007900028
const RCP_ERROR_CANCELED = 1007900992
const RCP_ERROR_COULD_NOT_RESOLVE_HOST = 1007900006
const RCP_ERROR_COULD_NOT_CONNECT = 1007900007
const RCP_ERROR_SSL_CONNECT = 1007900035
const RCP_ERROR_SERVER_RETURNED_NOTHING = 1007900052
const RCP_ERROR_SEND_FAILED = 1007900055
const RCP_ERROR_RECEIVE_FAILED = 1007900056
const RCP_ERROR_SSL_CERT = 1007900060
const RCP_ERROR_MAX_CONNECTION = 1007900089

// 音乐生成专用 RCP 客户端
// 1. connectMs=15s 快速失败（连接阶段）
// 2. transferMs=900s 兼容长音乐生成/编曲的耗时, music-2.6 单次可超过 10 分钟
// 3. inactivityMs=840s, 避免音乐生成服务端长时间无首字节时被空闲超时过早断开
// 4. 自动收集 timeInfo 用于诊断超时分布
export class MusicGenerationRcpClient {
  private static instance: MusicGenerationRcpClient | null = null
  private session: rcp.Session | null = null

  private constructor() {
  }

  static getInstance(): MusicGenerationRcpClient {
    if (MusicGenerationRcpClient.instance === null) {
      MusicGenerationRcpClient.instance = new MusicGenerationRcpClient()
    }
    return MusicGenerationRcpClient.instance
  }

  private getSession(): rcp.Session {
    if (this.session === null) {
      try {
        this.session = rcp.createSession({
          connectionConfiguration: {
            maxConnectionsPerHost: 4,
            maxTotalConnections: 16
          },
          requestConfiguration: {
            transfer: {
              autoRedirect: true,
              timeout: {
                connectMs: MUSIC_GEN_CONNECT_TIMEOUT_MS,
                transferMs: MUSIC_GEN_TRANSFER_TIMEOUT_MS,
                inactivityMs: MUSIC_GEN_INACTIVITY_TIMEOUT_MS
              }
            },
            tracing: {
              collectTimeInfo: true
            }
          }
        })
      } catch (error) {
        console.error('MusicGenRcp', `createSession failed: ${JSON.stringify(error)}`)
        throw new Error('RCP 网络会话创建失败')
      }
    }
    return this.session
  }

  async postJson(
    url: string,
    headers: Record<string, string>,
    body: string,
    controller?: HttpRequestController
  ): Promise<HttpResponse> {
    return await this.executeRequest(url, 'POST', headers, body, controller)
  }

  private async executeRequest(
    url: string,
    method: string,
    headers: Record<string, string>,
    content: rcp.RequestContent,
    controller?: HttpRequestController
  ): Promise<HttpResponse> {
    const session = this.getSession()
    const request = new rcp.Request(url, method, headers, content)
    let cancelId = ''
    if (controller !== undefined) {
      if (controller.isCancelled()) {
        return this.buildCancelledResponse()
      }
      cancelId = controller.registerCancelable((): void => {
        try {
          session.cancel(request)
        } catch (_error) {
        }
      })
    }
    try {
      const response = await session.fetch(request)
      this.logTimeInfo(url, response)
      return this.toHttpResponse(response)
    } catch (error) {
      const err = error as BusinessError
      const cancelled = controller !== undefined && controller.isCancelled()
      const message = this.formatError(err, cancelled)
      this.logRequestError(url, method, err, cancelled, message)
      return {
        success: false,
        statusCode: 0,
        data: '',
        errorMessage: message
      }
    } finally {
      if (controller !== undefined && cancelId !== '') {
        controller.unregisterCancelable(cancelId)
      }
    }
  }

  private toHttpResponse(response: rcp.Response): HttpResponse {
    let data = ''
    try {
      const text = response.toString()
      data = text !== null ? text : ''
    } catch (_error) {
      data = ''
    }
    const success = response.statusCode >= 200 && response.statusCode < 300
    return {
      success: success,
      statusCode: response.statusCode,
      data: data,
      errorMessage: success ? '' : `HTTP ${response.statusCode}`
    }
  }

  private buildCancelledResponse(): HttpResponse {
    return {
      success: false,
      statusCode: 0,
      data: '',
      errorMessage: '请求已取消'
    }
  }

  private logTimeInfo(url: string, response: rcp.Response): void {
    const timeInfo = response.timeInfo
    if (timeInfo === undefined) {
      return
    }
    console.info('MusicGenRcp',
      `${url} status=${response.statusCode} ` +
      `total=${timeInfo.totalTimeMs}ms ` +
      `dns=${timeInfo.nameLookupTimeMs}ms ` +
      `connect=${timeInfo.connectTimeMs}ms ` +
      `tls=${timeInfo.tlsHandshakeTimeMs}ms ` +
      `firstByte=${timeInfo.startTransferTimeMs}ms`)
  }

  private logRequestError(url: string, method: string, error: BusinessError, cancelled: boolean, mappedMessage: string): void {
    console.warn('MusicGenRcp',
      `${method} ${this.maskUrl(url)} failed ` +
      `code=${error.code} cancelled=${cancelled} ` +
      `message=${this.getErrorMessage(error)} mapped=${mappedMessage}`)
  }

  private maskUrl(url: string): string {
    const queryIndex = url.indexOf('?')
    if (queryIndex < 0) {
      return url
    }
    return `${url.substring(0, queryIndex)}?...`
  }

  private formatError(error: BusinessError, cancelled: boolean): string {
    if (cancelled) {
      return '请求已取消'
    }
    if (error.code === RCP_ERROR_CANCELED) {
      return '请求已取消'
    }
    if (error.code === RCP_ERROR_TIMEOUT) {
      return this.formatTimeoutError(this.getErrorMessage(error))
    }
    if (error.code === RCP_ERROR_COULD_NOT_RESOLVE_HOST) {
      return '域名解析失败，请检查服务地址是否正确'
    }
    if (error.code === RCP_ERROR_COULD_NOT_CONNECT) {
      return '无法连接到服务器，请检查网络连接或服务地址'
    }
    if (error.code === RCP_ERROR_SSL_CONNECT) {
      return 'SSL 连接失败，请检查服务地址是否支持 HTTPS'
    }
    if (error.code === RCP_ERROR_SERVER_RETURNED_NOTHING) {
      return '服务器未返回数据，请稍后重试'
    }
    if (error.code === RCP_ERROR_SEND_FAILED) {
      return '请求发送失败，请检查网络连接后重试'
    }
    if (error.code === RCP_ERROR_RECEIVE_FAILED) {
      return '响应接收失败，请检查网络连接后重试'
    }
    if (error.code === RCP_ERROR_SSL_CERT) {
      return 'SSL 证书验证失败，当前设备未信任该 HTTPS 证书链'
    }
    if (error.code === RCP_ERROR_MAX_CONNECTION) {
      return '网络连接数已达上限，请稍后重试'
    }
    if (error.message !== undefined && error.message !== '') {
      return error.message
    }
    return `网络请求失败 (code=${error.code})`
  }

  private formatTimeoutError(message: string): string {
    const lower = message.toLowerCase()
    if (lower.includes('connect')) {
      return '连接超时，请检查网络或服务地址是否正确'
    }
    if (lower.includes('inactivity')) {
      return '音乐生成长时间没有响应，已超时，请稍后重试'
    }
    if (lower.includes('transfer')) {
      return '音乐生成请求超时，请稍后重试'
    }
    return '音乐生成请求超时，请稍后重试'
  }

  private getErrorMessage(error: BusinessError): string {
    if (error.message !== undefined && error.message !== '') {
      return error.message
    }
    return ''
  }

  destroy(): void {
    if (this.session !== null) {
      try {
        this.session.close()
      } catch (_error) {
      }
      this.session = null
    }
  }
}

export function getMusicGenerationRcpClient(): MusicGenerationRcpClient {
  return MusicGenerationRcpClient.getInstance()
}
