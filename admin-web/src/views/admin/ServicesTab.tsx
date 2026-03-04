import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const ServicesTab: React.FC = () => {
  const [services, setServices] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<any>(null);

  useEffect(() => { load(); }, []);
  const load = async () => { const r = await adminApi.getServices(); if (r.success) setServices(r.data || []); setLoading(false); };

  const handleSave = async () => {
    if (!editing) return;
    const r = await adminApi.updateService(editing.id, {
      name: editing.name,
      pricePerMinute: editing.pricePerMinute,
      isActive: editing.isActive,
    });
    if (r.success) { setEditing(null); load(); }
    else alert(r.error);
  };

  const toggleActive = async (svc: any) => {
    await adminApi.updateService(svc.id, { isActive: !svc.isActive });
    load();
  };

  const fmt = (n: number) => n.toLocaleString('vi-VN');

  if (loading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <div className="space-y-6 animate-fade-in">
      <h2 className="text-2xl font-black text-white">⚙️ Cấu hình dịch vụ</h2>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {services.sort((a, b) => a.sortOrder - b.sortOrder).map(svc => (
          <div key={svc.id} className={`bg-gray-900 rounded-xl border p-5 transition-all ${svc.isActive ? 'border-gray-800' : 'border-red-900/30 opacity-60'}`}>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <span className="text-3xl">{svc.icon}</span>
                <div>
                  <h3 className="text-white font-bold">{svc.name}</h3>
                  <p className="text-gray-500 text-xs">Relay #{svc.relayIndex}</p>
                </div>
              </div>
              <button onClick={() => toggleActive(svc)} className={`w-11 h-6 rounded-full relative transition-all ${svc.isActive ? 'bg-emerald-500' : 'bg-gray-700'}`}>
                <div className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-all ${svc.isActive ? 'left-6' : 'left-1'}`} />
              </button>
            </div>

            <div className="bg-gray-800 rounded-lg p-3 flex items-center justify-between">
              <span className="text-gray-500 text-xs">Giá / phút</span>
              <span className="text-emerald-400 font-black text-lg">{fmt(svc.pricePerMinute)}đ</span>
            </div>

            <button onClick={() => setEditing({ ...svc })}
              className="w-full mt-3 bg-gray-800 hover:bg-gray-700 text-gray-400 py-2 rounded-lg text-xs font-bold transition">
              ✏️ Chỉnh sửa
            </button>
          </div>
        ))}
      </div>

      {/* Edit Modal */}
      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={() => setEditing(null)}>
          <div className="bg-gray-900 rounded-2xl p-6 w-full max-w-sm border border-gray-700" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-black text-white mb-4">{editing.icon} {editing.name}</h3>
            <div className="space-y-3">
              <div>
                <label className="text-xs text-gray-500 font-bold">Tên dịch vụ</label>
                <input type="text" value={editing.name} onChange={e => setEditing({ ...editing, name: e.target.value })}
                  className="w-full bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-700 focus:border-blue-500 focus:outline-none mt-1" />
              </div>
              <div>
                <label className="text-xs text-gray-500 font-bold">Giá / phút (VNĐ)</label>
                <input type="number" value={editing.pricePerMinute} onChange={e => setEditing({ ...editing, pricePerMinute: parseInt(e.target.value) || 0 })}
                  className="w-full bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-700 focus:border-blue-500 focus:outline-none mt-1" />
              </div>
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={() => setEditing(null)} className="flex-1 bg-gray-800 text-gray-400 py-2 rounded-lg text-sm font-bold">Hủy</button>
              <button onClick={handleSave} className="flex-1 bg-blue-600 text-white py-2 rounded-lg text-sm font-bold">💾 Lưu</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
