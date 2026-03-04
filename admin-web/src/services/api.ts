const BASE = '/api';

async function request<T = any>(path: string, options?: RequestInit): Promise<{ success: boolean; data?: T; error?: string }> {
  try {
    const token = localStorage.getItem('admin_token');
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const res = await fetch(`${BASE}${path}`, { ...options, headers: { ...headers, ...options?.headers } });
    return await res.json();
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export const adminApi = {
  login: (username: string, password: string) =>
    request('/admin/login', { method: 'POST', body: JSON.stringify({ username, password }) }),

  getDashboard: () => request('/admin/dashboard'),
  getStations: () => request('/admin/stations'),
  getStation: (id: string) => request(`/admin/stations/${id}`),
  createStation: (data: any) => request('/admin/stations', { method: 'POST', body: JSON.stringify(data) }),
  updateStation: (id: string, data: any) => request(`/admin/stations/${id}`, { method: 'PUT', body: JSON.stringify(data) }),

  getSessions: (params?: Record<string, string>) => {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return request(`/admin/sessions${qs}`);
  },
  getTransactions: (params?: Record<string, string>) => {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return request(`/admin/transactions${qs}`);
  },

  getServices: () => request('/admin/services'),
  updateService: (id: string, data: any) => request(`/admin/services/${id}`, { method: 'PUT', body: JSON.stringify(data) }),

  getConfig: () => request('/admin/config'),
  updateConfig: (data: any) => request('/admin/config', { method: 'PUT', body: JSON.stringify(data) }),

  getStationLogs: (id: string, limit = 50) => request(`/admin/stations/${id}/logs?limit=${limit}`),
  getRevenueReport: (days = 30) => request(`/admin/reports/revenue?days=${days}`),

  // Demo
  demoConfirmPayment: (refCode: string, amount?: number) =>
    request('/payment/demo-confirm', { method: 'POST', body: JSON.stringify({ refCode, amount }) }),
};
