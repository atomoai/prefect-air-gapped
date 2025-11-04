import { showToast } from '@prefecthq/prefect-design'
import { AxiosError, AxiosInstance, isAxiosError } from 'axios'
import { h, ref } from 'vue'
import ApiStatusToast from '@/components/ApiStatusToast.vue'

const ranges = [500]
const statuses = [401, 403]
const codes = ['ERR_NETWORK']

const shown = ref(false)

export function setupApiStatusInterceptor(axiosInstance: AxiosInstance): void {
  if (shown.value) {
    return
  }

  const interceptorId = axiosInstance.interceptors.response.use(undefined, interceptor)

  function isInterceptedError(error: AxiosError): boolean {
    if (!isAxiosError(error)) {
      return false
    }

    const status = error.response?.status

    if (typeof status === 'number') {
      return statuses.includes(status) || ranges.some(range => status >= range && status < range + 100)
    }

    if (error.code) {
      return codes.includes(error.code)
    }

    return false
  }

  function interceptor(error: AxiosError): Promise<AxiosError> {
    if (isInterceptedError(error) && !shown.value) {
      shown.value = true
      const status = error.response?.status
      const kind = status === 401 || status === 403 ? 'auth' : 'other'
      const toastComponent = h(ApiStatusToast, { kind })
      showToast(toastComponent, 'error', { dismissible: true, timeout: false })
      ejectInterceptor()
    }
    return Promise.reject(error)
  }

  function ejectInterceptor(): void {
    axiosInstance.interceptors.response.eject(interceptorId)
  }
}