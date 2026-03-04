import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const SessionsTab: React.FC = () => {
  const [sessions, setSessions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');

  useEffect(() => { load(); }, [filter]);
  const load = async () => {
    const params: Record<string, string> = { limit: '50' };
    if (filter) params.status = filter;
    const r = await adminApi.getSessions(params);
    if (r.success) setSessions(r.data || []);
    setLoading(false);
  };

  const fmt = (n: number) => n.toLocaleString('vi-VN');
  const time = (ts: number) => new Date(ts).toLocaleString('vi-VN');

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black text-white">🚗 Phiên rửa xe</h2>
        <div className="flex gap-2">
          {['', 'ACTIVE', 'COMPLETED', 'PAUSED'].map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-lg text-xs font-bold transition ${filter === f ? 'bg-blue-600 text-white' : 'bg-gray-800 text-gray-400 hover:text-white'}`}>
              {f || 'Tất cả'}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>
      ) : sessions.length === 0 ? (
        <p className="text-gray-600 text-center py-10">Không có phiên nào</p>
      ) : (
        <div className="space-y-3">
          {sessions.map(s => (
            <div key={s.id} className="bg-gray-900 rounded-xl border border-gray-800 p-4">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  <StatusBadge status={s.status} />
                  <div>
                    <p className="text-white text-sm font-bold">{s.stationId}</p>
                    <p className="text-gray-500 text-xs">{time(s.startTime)}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-emerald-400 font-bold">{fmt(s.totalDeposited)}đ</p>
                  <p className="text-gray-500 text-xs">Đã dùng: {fmt(s.totalUsed)}đ</p>
                </div>
              </div>

              {/* Service usage */}
              {s.serviceUsage && s.serviceUsage.length > 0 && (
                <div className="flex flex-wrap gap-2 mt-2">
                  {s.serviceUsage.map((u: any, i: number) => (
                    <span key={i} className="bg-gray-800 text-gray-300 px-2 py-1 rounded text-xs">
                      {u.serviceName} · {Math.round(u.durationSeconds / 60)}p · {fmt(u.cost)}đ
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

const StatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const styles: Record<string, string> = {
    ACTIVE: 'bg-emerald-500/10 text-emerald-400',
    PAUSED: 'bg-yellow-500/10 text-yellow-400',
    COMPLETED: 'bg-gray-700/50 text-gray-400',
    EXPIRED: 'bg-red-500/10 text-red-400',
    ERROR: 'bg-red-500/10 text-red-400',
  };
  const labels: Record<string, string> = {
    ACTIVE: 'Đang dùng', PAUSED: 'Tạm dừng', COMPLETED: 'Hoàn tất', EXPIRED: 'Hết giờ', ERROR: 'Lỗi',
  };
  return <span className={`text-[10px] font-bold px-2 py-1 rounded-full ${styles[status] || 'bg-gray-700 text-gray-400'}`}>{labels[status] || status}</span>;
};
