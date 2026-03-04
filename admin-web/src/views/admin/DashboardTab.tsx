import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const DashboardTab: React.FC = () => {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => { load(); const i = setInterval(load, 30000); return () => clearInterval(i); }, []);

  const load = async () => {
    const res = await adminApi.getDashboard();
    if (res.success) setData(res.data);
    setLoading(false);
  };

  if (loading) return <Spinner />;
  if (!data) return <p className="text-red-400">Không tải được dữ liệu</p>;

  const fmt = (n: number) => n.toLocaleString('vi-VN');

  return (
    <div className="space-y-6 animate-fade-in">
      <h2 className="text-2xl font-black text-white">📊 Dashboard</h2>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon="🏪" label="Trạm online" value={`${data.stations.online}/${data.stations.total}`} color="emerald" />
        <StatCard icon="🚗" label="Phiên hôm nay" value={data.today.sessions} color="blue" />
        <StatCard icon="💰" label="Doanh thu hôm nay" value={`${fmt(data.today.revenue)}đ`} color="yellow" />
        <StatCard icon="📥" label="Nạp tiền hôm nay" value={`${fmt(data.today.deposits)}đ`} color="purple" />
      </div>

      {/* Station List */}
      <div className="bg-gray-900 rounded-xl border border-gray-800 p-5">
        <h3 className="text-sm font-bold text-white mb-4">🏪 Trạng thái trạm</h3>
        <div className="space-y-3">
          {(data.stationList || []).map((s: any) => (
            <div key={s.id} className="flex items-center justify-between bg-gray-800 rounded-lg p-3">
              <div className="flex items-center gap-3">
                <div className={`w-3 h-3 rounded-full ${
                  s.status === 'IN_USE' ? 'bg-yellow-400 animate-pulse' :
                  s.status === 'ONLINE' ? 'bg-emerald-400' : 'bg-red-400'
                }`} />
                <div>
                  <p className="text-white text-sm font-bold">{s.name}</p>
                  <p className="text-gray-500 text-xs">{s.location}</p>
                </div>
              </div>
              <div className="text-right">
                <span className={`text-xs font-bold px-2 py-1 rounded-full ${
                  s.status === 'IN_USE' ? 'bg-yellow-500/10 text-yellow-400' :
                  s.status === 'ONLINE' ? 'bg-emerald-500/10 text-emerald-400' :
                  'bg-red-500/10 text-red-400'
                }`}>
                  {s.status === 'IN_USE' ? 'Đang dùng' : s.status === 'ONLINE' ? 'Sẵn sàng' : 'Offline'}
                </span>
                <p className="text-gray-600 text-[10px] mt-1">
                  ESP32: {s.esp32Status === 'ONLINE' ? '✅' : '❌'}
                </p>
              </div>
            </div>
          ))}
          {(!data.stationList || data.stationList.length === 0) && (
            <p className="text-gray-600 text-center py-4">Chưa có trạm nào</p>
          )}
        </div>
      </div>

      {/* Service Breakdown */}
      {Object.keys(data.serviceBreakdown || {}).length > 0 && (
        <div className="bg-gray-900 rounded-xl border border-gray-800 p-5">
          <h3 className="text-sm font-bold text-white mb-4">📋 Dịch vụ hôm nay</h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {Object.entries(data.serviceBreakdown).map(([name, stats]: [string, any]) => (
              <div key={name} className="bg-gray-800 rounded-lg p-3">
                <p className="text-white text-sm font-bold">{name}</p>
                <p className="text-blue-400 text-xs">{stats.count} lần · {Math.round(stats.minutes)} phút</p>
                <p className="text-emerald-400 text-sm font-bold">{fmt(stats.revenue)}đ</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

const StatCard: React.FC<{ icon: string; label: string; value: string | number; color: string }> = ({ icon, label, value, color }) => {
  const colors: Record<string, string> = {
    emerald: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
    blue: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
    yellow: 'text-yellow-400 bg-yellow-500/10 border-yellow-500/20',
    purple: 'text-purple-400 bg-purple-500/10 border-purple-500/20',
  };
  return (
    <div className={`rounded-xl p-4 border ${colors[color]} animate-slide-up`}>
      <div className="flex items-center gap-2 mb-2">
        <span className="text-xl">{icon}</span>
        <span className="text-[10px] uppercase tracking-wider font-bold opacity-70">{label}</span>
      </div>
      <p className="text-2xl font-black">{value}</p>
    </div>
  );
};

const Spinner = () => (
  <div className="flex items-center justify-center py-20">
    <div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
  </div>
);
