import React, { useState, useEffect } from 'react';
import { adminApi } from '../../services/api';

export const ConfigTab: React.FC = () => {
  const [config, setConfig] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [edited, setEdited] = useState(false);

  useEffect(() => { load(); }, []);
  const load = async () => { const r = await adminApi.getConfig(); if (r.success) setConfig(r.data); setLoading(false); };

  const update = (key: string, value: any) => {
    const parts = key.split('.');
    const c = JSON.parse(JSON.stringify(config));
    let obj = c;
    for (let i = 0; i < parts.length - 1; i++) obj = obj[parts[i]];
    obj[parts[parts.length - 1]] = value;
    setConfig(c);
    setEdited(true);
  };

  const handleSave = async () => {
    setSaving(true);
    const r = await adminApi.updateConfig(config);
    setSaving(false);
    if (r.success) { setEdited(false); alert('Đã lưu!'); }
    else alert(r.error);
  };

  if (loading) return <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" /></div>;
  if (!config) return <p className="text-red-400">Lỗi tải cấu hình</p>;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black text-white">🔧 Cấu hình hệ thống</h2>
        <button onClick={handleSave} disabled={!edited || saving}
          className={`px-4 py-2 rounded-lg text-sm font-bold transition ${edited ? 'bg-blue-600 hover:bg-blue-500 text-white' : 'bg-gray-800 text-gray-500'}`}>
          {saving ? 'Đang lưu...' : edited ? '💾 Lưu' : 'Không thay đổi'}
        </button>
      </div>

      <Section title="💰 Thanh toán">
        <div className="grid grid-cols-2 gap-4">
          <Field label="Nạp tối thiểu (VNĐ)" type="number" value={config.minDeposit} onChange={v => update('minDeposit', parseInt(v))} />
          <Field label="Tạm dừng tối đa (phút)" type="number" value={config.maxPauseMinutes} onChange={v => update('maxPauseMinutes', parseInt(v))} />
        </div>
      </Section>

      <Section title="🔄 Auto Restart">
        <Field label="Restart sau (phút) mất kết nối" type="number" value={config.autoRestartMinutes} onChange={v => update('autoRestartMinutes', parseInt(v))} />
      </Section>

      <Section title="🏦 SePay">
        <div className="grid grid-cols-2 gap-4">
          <Field label="API Key" value={config.sepay?.apiKey || ''} onChange={v => update('sepay.apiKey', v)} />
          <Field label="Merchant ID" value={config.sepay?.merchantId || ''} onChange={v => update('sepay.merchantId', v)} />
          <Field label="Số tài khoản" value={config.sepay?.bankAccount || ''} onChange={v => update('sepay.bankAccount', v)} />
          <Field label="Mã ngân hàng" value={config.sepay?.bankCode || ''} onChange={v => update('sepay.bankCode', v)} />
          <Field label="Webhook Secret" value={config.sepay?.webhookSecret || ''} onChange={v => update('sepay.webhookSecret', v)} />
        </div>
      </Section>

      <Section title="📱 Telegram">
        <div className="space-y-3">
          <Field label="Bot Token" value={config.telegram?.botToken || ''} onChange={v => update('telegram.botToken', v)} />
          <Field label="Chat IDs (cách nhau bởi dấu phẩy)" value={(config.telegram?.alertChatIds || []).join(',')}
            onChange={v => update('telegram.alertChatIds', v.split(',').map((s: string) => s.trim()).filter(Boolean))} />
        </div>
      </Section>
    </div>
  );
};

const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <div className="bg-gray-900 rounded-xl border border-gray-800 p-5">
    <h3 className="text-sm font-bold text-white mb-4">{title}</h3>
    {children}
  </div>
);

const Field: React.FC<{ label: string; value: string | number; type?: string; onChange: (v: string) => void }> = ({ label, value, type, onChange }) => (
  <div>
    <label className="text-xs text-gray-500 font-bold">{label}</label>
    <input type={type || 'text'} value={value} onChange={e => onChange(e.target.value)}
      className="w-full bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-700 focus:border-blue-500 focus:outline-none mt-1" />
  </div>
);
