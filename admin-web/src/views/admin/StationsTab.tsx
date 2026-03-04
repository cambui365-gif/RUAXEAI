import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const StationsTab: React.FC = () => {
  const [stations, setStations] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({ id: '', name: '', location: '', tabletId: '' });

  useEffect(() => { load(); }, []);
  const load = async () => { const r = await adminApi.getStations(); if (r.success) setStations(r.data || []); setLoading(false); };

  const handleCreate = async () => {
    if (!form.id || !form.name) return alert('ID và Tên trạm bắt buộc');
    const r = await adminApi.createStation(form);
    if (r.success) { setShowCreate(false); setForm({ id: '', name: '', location: '', tabletId: '' }); load(); }
    else alert(r.error);
  };

  if (loading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black text-white">🏪 Quản lý trạm</h2>
        <button onClick={() => setShowCreate(true)} className="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-lg text-sm font-bold">
          + Thêm trạm
        </button>
      </div>

      <div className="grid gap-4">
        {stations.map(s => (
          <div key={s.id} className="bg-gray-900 rounded-xl border border-gray-800 p-5">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-3">
                <div className={`w-4 h-4 rounded-full ${s.status === 'IN_USE' ? 'bg-yellow-400 animate-pulse' : s.status === 'ONLINE' ? 'bg-emerald-400' : 'bg-red-400'}`} />
                <div>
                  <h3 className="text-white font-bold">{s.name}</h3>
                  <p className="text-gray-500 text-xs">{s.location || 'Chưa cập nhật'}</p>
                </div>
              </div>
              <span className="text-xs font-mono text-gray-600">{s.id}</span>
            </div>
            <div className="grid grid-cols-4 gap-3 text-center">
              <MiniStat label="Trạng thái" value={s.status} />
              <MiniStat label="ESP32" value={s.esp32Status} />
              <MiniStat label="Tablet" value={s.tabletId || '—'} />
              <MiniStat label="Heartbeat" value={s.lastHeartbeat ? new Date(s.lastHeartbeat).toLocaleTimeString('vi') : '—'} />
            </div>
          </div>
        ))}
        {stations.length === 0 && <p className="text-gray-600 text-center py-10">Chưa có trạm nào. Bấm "+ Thêm trạm" để tạo.</p>}
      </div>

      {/* Create Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={() => setShowCreate(false)}>
          <div className="bg-gray-900 rounded-2xl p-6 w-full max-w-md border border-gray-700" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-black text-white mb-4">Thêm trạm mới</h3>
            <div className="space-y-3">
              <Input label="ID trạm" placeholder="station-001" value={form.id} onChange={v => setForm({...form, id: v})} />
              <Input label="Tên trạm" placeholder="Trạm 01 - Quận 7" value={form.name} onChange={v => setForm({...form, name: v})} />
              <Input label="Địa chỉ" placeholder="123 Nguyễn Văn Linh" value={form.location} onChange={v => setForm({...form, location: v})} />
              <Input label="Tablet ID" placeholder="tablet-001" value={form.tabletId} onChange={v => setForm({...form, tabletId: v})} />
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={() => setShowCreate(false)} className="flex-1 bg-gray-800 text-gray-400 py-2 rounded-lg text-sm font-bold">Hủy</button>
              <button onClick={handleCreate} className="flex-1 bg-blue-600 text-white py-2 rounded-lg text-sm font-bold">Tạo trạm</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

const MiniStat: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div className="bg-gray-800 rounded-lg p-2">
    <p className="text-[9px] text-gray-500 uppercase">{label}</p>
    <p className="text-white text-xs font-bold truncate">{value}</p>
  </div>
);

const Input: React.FC<{ label: string; placeholder: string; value: string; onChange: (v: string) => void }> = ({ label, placeholder, value, onChange }) => (
  <div>
    <label className="text-xs text-gray-500 font-bold">{label}</label>
    <input type="text" placeholder={placeholder} value={value} onChange={e => onChange(e.target.value)}
      className="w-full bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-700 focus:border-blue-500 focus:outline-none mt-1" />
  </div>
);
