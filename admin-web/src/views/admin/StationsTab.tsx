import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const StationsTab: React.FC = () => {
  const [stations, setStations] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [selectedStation, setSelectedStation] = useState<any>(null);
  const [form, setForm] = useState({ id: '', name: '', location: '', tabletId: '', imageUrl: '' });

  useEffect(() => { load(); }, []);
  const load = async () => { 
    const r = await adminApi.getStations(); 
    if (r.success) setStations(r.data || []); 
    setLoading(false); 
  };

  const handleCreate = async () => {
    if (!form.id || !form.name) return alert('ID và Tên trạm bắt buộc');
    const r = await adminApi.createStation(form);
    if (r.success) { 
      setShowCreate(false); 
      setForm({ id: '', name: '', location: '', tabletId: '', imageUrl: '' }); 
      load(); 
    }
    else alert(r.error);
  };

  const handleEdit = (station: any) => {
    setForm({
      id: station.id,
      name: station.name,
      location: station.location || '',
      tabletId: station.tabletId || '',
      imageUrl: station.imageUrl || '',
    });
    setShowCreate(true);
  };

  const handleUpdate = async () => {
    const { id, ...data } = form;
    const r = await adminApi.updateStation(id, data);
    if (r.success) { 
      setShowCreate(false); 
      setForm({ id: '', name: '', location: '', tabletId: '', imageUrl: '' }); 
      load(); 
    }
    else alert(r.error);
  };

  const handleToggleLock = async (station: any) => {
    const newStatus = station.status === 'MAINTENANCE' ? 'ONLINE' : 'MAINTENANCE';
    const r = await adminApi.updateStation(station.id, { status: newStatus });
    if (r.success) load();
    else alert(r.error);
  };

  if (loading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black text-white">🏪 Quản lý trạm</h2>
        <button onClick={() => { setForm({ id: '', name: '', location: '', tabletId: '', imageUrl: '' }); setShowCreate(true); }} 
          className="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-lg text-sm font-bold">
          + Thêm trạm
        </button>
      </div>

      <div className="grid gap-4">
        {stations.map(s => (
          <div key={s.id} className={`bg-gray-900 rounded-xl border p-5 ${s.status === 'MAINTENANCE' ? 'border-red-700 opacity-70' : 'border-gray-800'}`}>
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-3">
                {s.imageUrl ? (
                  <img src={s.imageUrl} alt={s.name} className="w-12 h-12 rounded-lg object-cover" />
                ) : (
                  <div className="w-12 h-12 bg-gray-800 rounded-lg flex items-center justify-center text-2xl">🏪</div>
                )}
                <div className={`w-4 h-4 rounded-full ${
                  s.status === 'MAINTENANCE' ? 'bg-red-500' :
                  s.status === 'IN_USE' ? 'bg-yellow-400 animate-pulse' : 
                  s.status === 'ONLINE' ? 'bg-emerald-400' : 'bg-red-400'
                }`} />
                <div>
                  <h3 className="text-white font-bold">{s.name}</h3>
                  <p className="text-gray-500 text-xs">{s.location || 'Chưa cập nhật'}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {s.status === 'MAINTENANCE' && <span className="text-xs bg-red-900 text-red-300 px-2 py-1 rounded font-bold">🔒 Bảo trì</span>}
                <span className="text-xs font-mono text-gray-600">{s.id}</span>
              </div>
            </div>
            <div className="grid grid-cols-4 gap-3 text-center mb-3">
              <MiniStat label="Trạng thái" value={s.status} />
              <MiniStat label="ESP32" value={s.esp32Status} />
              <MiniStat label="Tablet" value={s.tabletId || '—'} />
              <MiniStat label="Heartbeat" value={s.lastHeartbeat ? new Date(s.lastHeartbeat).toLocaleTimeString('vi') : '—'} />
            </div>
            <div className="flex gap-2">
              <button onClick={() => setSelectedStation(s)} 
                className="flex-1 bg-blue-600 hover:bg-blue-500 text-white py-2 rounded-lg text-xs font-bold">
                📊 Chi tiết
              </button>
              <button onClick={() => handleEdit(s)} 
                className="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 py-2 rounded-lg text-xs font-bold">
                ✏️ Sửa
              </button>
              <button onClick={() => handleToggleLock(s)} 
                className={`flex-1 py-2 rounded-lg text-xs font-bold ${
                  s.status === 'MAINTENANCE' 
                    ? 'bg-emerald-600 hover:bg-emerald-500 text-white' 
                    : 'bg-red-600 hover:bg-red-500 text-white'
                }`}>
                {s.status === 'MAINTENANCE' ? '🔓 Mở' : '🔒 Khóa'}
              </button>
            </div>
          </div>
        ))}
        {stations.length === 0 && <p className="text-gray-600 text-center py-10">Chưa có trạm nào. Bấm "+ Thêm trạm" để tạo.</p>}
      </div>

      {/* Create/Edit Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={() => setShowCreate(false)}>
          <div className="bg-gray-900 rounded-2xl p-6 w-full max-w-md border border-gray-700" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-black text-white mb-4">{form.id ? '✏️ Sửa trạm' : 'Thêm trạm mới'}</h3>
            <div className="space-y-3">
              <Input label="ID trạm" placeholder="station-001" value={form.id} onChange={v => setForm({...form, id: v})} disabled={!!form.id} />
              <Input label="Tên trạm" placeholder="Trạm 01 - Quận 7" value={form.name} onChange={v => setForm({...form, name: v})} />
              <Input label="Địa chỉ" placeholder="123 Nguyễn Văn Linh" value={form.location} onChange={v => setForm({...form, location: v})} />
              <Input label="Tablet ID" placeholder="tablet-001" value={form.tabletId} onChange={v => setForm({...form, tabletId: v})} />
              <Input label="URL hình ảnh" placeholder="https://..." value={form.imageUrl} onChange={v => setForm({...form, imageUrl: v})} />
            </div>
            <div className="flex gap-3 mt-6">
              <button onClick={() => setShowCreate(false)} className="flex-1 bg-gray-800 text-gray-400 py-2 rounded-lg text-sm font-bold">Hủy</button>
              <button onClick={form.id ? handleUpdate : handleCreate} className="flex-1 bg-blue-600 text-white py-2 rounded-lg text-sm font-bold">
                {form.id ? '💾 Cập nhật' : 'Tạo trạm'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Station Detail Modal */}
      {selectedStation && (
        <StationDetailModal station={selectedStation} onClose={() => setSelectedStation(null)} />
      )}
    </div>
  );
};

const StationDetailModal: React.FC<{ station: any; onClose: () => void }> = ({ station, onClose }) => {
  const [transactions, setTransactions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadTransactions();
  }, [station.id]);

  const loadTransactions = async () => {
    const r = await adminApi.getTransactions({ stationId: station.id, limit: '20' });
    if (r.success) setTransactions(r.data || []);
    setLoading(false);
  };

  const fmt = (n: number) => n.toLocaleString('vi-VN');

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={onClose}>
      <div className="bg-gray-900 rounded-2xl p-6 w-full max-w-3xl border border-gray-700 max-h-[90vh] overflow-auto" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            {station.imageUrl && <img src={station.imageUrl} alt={station.name} className="w-16 h-16 rounded-lg object-cover" />}
            <div>
              <h3 className="text-2xl font-black text-white">{station.name}</h3>
              <p className="text-gray-500 text-sm">{station.location}</p>
            </div>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-white text-2xl">×</button>
        </div>

        <div className="grid grid-cols-3 gap-4 mb-6">
          <StatCard label="Trạng thái" value={station.status} color="blue" />
          <StatCard label="ESP32" value={station.esp32Status} color="green" />
          <StatCard label="Tablet" value={station.tabletId || 'Chưa có'} color="purple" />
        </div>

        <h4 className="text-lg font-bold text-white mb-3">📜 Lịch sử giao dịch</h4>
        {loading ? (
          <div className="flex justify-center py-10"><div className="w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <div className="space-y-2 max-h-96 overflow-auto">
            {transactions.map((tx, i) => (
              <div key={i} className="bg-gray-800 rounded-lg p-3 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{tx.type === 'DEPOSIT' ? '💰' : '💳'}</span>
                  <div>
                    <p className="text-white font-bold text-sm">{tx.type === 'DEPOSIT' ? 'Nạp tiền' : 'Thanh toán'}</p>
                    <p className="text-gray-500 text-xs">{new Date(tx.timestamp).toLocaleString('vi')}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`font-bold ${tx.type === 'DEPOSIT' ? 'text-emerald-400' : 'text-blue-400'}`}>
                    {tx.type === 'DEPOSIT' ? '+' : '-'}{fmt(tx.amount)}đ
                  </p>
                  {tx.refCode && <p className="text-gray-600 text-xs font-mono">{tx.refCode}</p>}
                </div>
              </div>
            ))}
            {transactions.length === 0 && <p className="text-gray-600 text-center py-6">Chưa có giao dịch nào</p>}
          </div>
        )}
      </div>
    </div>
  );
};

const StatCard: React.FC<{ label: string; value: string; color: string }> = ({ label, value, color }) => (
  <div className={`bg-gray-800 rounded-lg p-3 border-l-4 border-${color}-500`}>
    <p className="text-gray-500 text-xs uppercase">{label}</p>
    <p className="text-white text-lg font-bold">{value}</p>
  </div>
);

const MiniStat: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div className="bg-gray-800 rounded-lg p-2">
    <p className="text-[9px] text-gray-500 uppercase">{label}</p>
    <p className="text-white text-xs font-bold truncate">{value}</p>
  </div>
);

const Input: React.FC<{ label: string; placeholder: string; value: string; onChange: (v: string) => void; disabled?: boolean }> = 
  ({ label, placeholder, value, onChange, disabled }) => (
  <div>
    <label className="text-xs text-gray-500 font-bold">{label}</label>
    <input type="text" placeholder={placeholder} value={value} onChange={e => onChange(e.target.value)} disabled={disabled}
      className="w-full bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-700 focus:border-blue-500 focus:outline-none mt-1 disabled:opacity-50 disabled:cursor-not-allowed" />
  </div>
);
