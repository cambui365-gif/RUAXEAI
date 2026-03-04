import React, { useState, useEffect } from 'react';
import { adminApi } from './services/api';
import { LoginPage } from './views/admin/LoginPage';
import { DashboardTab } from './views/admin/DashboardTab';
import { StationsTab } from './views/admin/StationsTab';
import { SessionsTab } from './views/admin/SessionsTab';
import { ServicesTab } from './views/admin/ServicesTab';
import { ConfigTab } from './views/admin/ConfigTab';

type Tab = 'dashboard' | 'stations' | 'sessions' | 'services' | 'config';

const tabs: Array<{ id: Tab; label: string; icon: string }> = [
  { id: 'dashboard', label: 'Dashboard', icon: '📊' },
  { id: 'stations', label: 'Trạm', icon: '🏪' },
  { id: 'sessions', label: 'Phiên rửa', icon: '🚗' },
  { id: 'services', label: 'Dịch vụ', icon: '⚙️' },
  { id: 'config', label: 'Cấu hình', icon: '🔧' },
];

const App: React.FC = () => {
  const [token, setToken] = useState(localStorage.getItem('admin_token'));
  const [admin, setAdmin] = useState<any>(null);
  const [tab, setTab] = useState<Tab>('dashboard');
  const [sidebarOpen, setSidebarOpen] = useState(true);

  useEffect(() => {
    if (token) {
      // Verify token by fetching dashboard
      adminApi.getDashboard().then(res => {
        if (!res.success) { logout(); }
      });
    }
  }, [token]);

  const handleLogin = async (username: string, password: string) => {
    const res = await adminApi.login(username, password);
    if (res.success && res.data) {
      localStorage.setItem('admin_token', res.data.token);
      setToken(res.data.token);
      setAdmin(res.data.admin);
      return true;
    }
    return false;
  };

  const logout = () => {
    localStorage.removeItem('admin_token');
    setToken(null);
    setAdmin(null);
  };

  if (!token) return <LoginPage onLogin={handleLogin} />;

  return (
    <div className="min-h-screen bg-gray-950 flex">
      {/* Sidebar */}
      <aside className={`${sidebarOpen ? 'w-60' : 'w-16'} bg-gray-900 border-r border-gray-800 flex flex-col transition-all duration-300`}>
        <div className="p-4 border-b border-gray-800 flex items-center justify-between">
          {sidebarOpen && (
            <div>
              <h1 className="text-lg font-black text-white">🚗 RUAXEAI</h1>
              <p className="text-[10px] text-gray-500">Admin Dashboard</p>
            </div>
          )}
          <button onClick={() => setSidebarOpen(!sidebarOpen)} className="text-gray-400 hover:text-white p-1">
            {sidebarOpen ? '◀' : '▶'}
          </button>
        </div>

        <nav className="flex-1 py-2">
          {tabs.map(t => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`w-full flex items-center gap-3 px-4 py-3 text-sm transition-all ${
                tab === t.id
                  ? 'bg-blue-600/10 text-blue-400 border-r-2 border-blue-500'
                  : 'text-gray-400 hover:text-white hover:bg-gray-800'
              }`}
            >
              <span className="text-lg">{t.icon}</span>
              {sidebarOpen && <span className="flex-1 text-left font-medium">{t.label}</span>}
            </button>
          ))}
        </nav>

        <div className="p-4 border-t border-gray-800">
          {sidebarOpen && admin && (
            <p className="text-xs text-gray-500 mb-2">👤 {admin.name} ({admin.role})</p>
          )}
          <button onClick={logout} className="w-full text-left text-sm text-gray-500 hover:text-red-400 transition flex items-center gap-2">
            <span>🚪</span>
            {sidebarOpen && <span>Đăng xuất</span>}
          </button>
        </div>
      </aside>

      {/* Main */}
      <main className="flex-1 overflow-auto">
        <div className="max-w-7xl mx-auto p-6">
          {tab === 'dashboard' && <DashboardTab />}
          {tab === 'stations' && <StationsTab />}
          {tab === 'sessions' && <SessionsTab />}
          {tab === 'services' && <ServicesTab />}
          {tab === 'config' && <ConfigTab />}
        </div>
      </main>
    </div>
  );
};

export default App;
