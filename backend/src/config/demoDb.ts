/**
 * In-memory database for DEMO mode
 * Replaces Firebase Firestore when DEMO_MODE=true
 */

type Doc = Record<string, any>;

class InMemoryCollection {
  private docs: Map<string, Doc> = new Map();
  private autoIdCounter = 0;

  doc(id?: string): InMemoryDocRef {
    const docId = id || `auto_${++this.autoIdCounter}_${Date.now()}`;
    return new InMemoryDocRef(this, docId);
  }

  add(data: Doc): InMemoryDocRef {
    const id = `auto_${++this.autoIdCounter}_${Date.now()}`;
    this.docs.set(id, { ...data, _id: id });
    return new InMemoryDocRef(this, id);
  }

  _get(id: string): Doc | undefined { return this.docs.get(id); }
  _set(id: string, data: Doc) { this.docs.set(id, { ...data }); }
  _update(id: string, data: Partial<Doc>) {
    const existing = this.docs.get(id);
    if (existing) this.docs.set(id, { ...existing, ...data });
  }
  _delete(id: string) { this.docs.delete(id); }
  _all(): Array<{ id: string; data: Doc }> {
    return Array.from(this.docs.entries()).map(([id, data]) => ({ id, data }));
  }

  where(field: string, op: string, value: any): InMemoryQuery {
    return new InMemoryQuery(this).where(field, op, value);
  }
  orderBy(field: string, direction: string = 'asc'): InMemoryQuery {
    return new InMemoryQuery(this).orderBy(field, direction);
  }
  limit(n: number): InMemoryQuery {
    return new InMemoryQuery(this).limit(n);
  }
  async get(): Promise<InMemorySnapshot> {
    return new InMemoryQuery(this).get();
  }
}

class InMemoryDocRef {
  constructor(public collection: InMemoryCollection, public id: string) {}
  async get() {
    const doc = this.collection._get(this.id);
    return { exists: !!doc, data: () => doc ? { ...doc } : undefined, id: this.id };
  }
  async set(data: Doc) { this.collection._set(this.id, data); }
  async update(data: Partial<Doc>) { this.collection._update(this.id, data); }
  async delete() { this.collection._delete(this.id); }
}

class InMemoryQuery {
  private filters: Array<{ field: string; op: string; value: any }> = [];
  private ordering: Array<{ field: string; direction: string }> = [];
  private limitCount = Infinity;

  constructor(private collection: InMemoryCollection) {}

  where(field: string, op: string, value: any) { this.filters.push({ field, op, value }); return this; }
  orderBy(field: string, direction = 'asc') { this.ordering.push({ field, direction }); return this; }
  limit(n: number) { this.limitCount = n; return this; }

  async get(): Promise<InMemorySnapshot> {
    let results = this.collection._all();
    for (const f of this.filters) {
      results = results.filter(({ data }) => {
        const v = getNestedField(data, f.field);
        switch (f.op) {
          case '==': return v === f.value;
          case '!=': return v !== f.value;
          case '>': return v > f.value;
          case '>=': return v >= f.value;
          case '<': return v < f.value;
          case '<=': return v <= f.value;
          case 'in': return Array.isArray(f.value) && f.value.includes(v);
          default: return true;
        }
      });
    }
    for (const o of this.ordering) {
      results.sort((a, b) => {
        const av = getNestedField(a.data, o.field) || 0;
        const bv = getNestedField(b.data, o.field) || 0;
        return o.direction === 'desc' ? (bv > av ? 1 : -1) : (av > bv ? 1 : -1);
      });
    }
    return new InMemorySnapshot(results.slice(0, this.limitCount));
  }
}

class InMemorySnapshot {
  docs: Array<{ id: string; data: () => Doc; ref: { id: string } }>;
  size: number;
  empty: boolean;
  constructor(results: Array<{ id: string; data: Doc }>) {
    this.docs = results.map(r => ({ id: r.id, data: () => ({ ...r.data }), ref: { id: r.id } }));
    this.size = results.length;
    this.empty = results.length === 0;
  }
  forEach(cb: (doc: { id: string; data: () => Doc; ref: { id: string } }) => void) { this.docs.forEach(cb); }
}

class InMemoryTransaction {
  private writes: Array<{ type: string; ref: InMemoryDocRef; data?: any }> = [];
  async get(ref: InMemoryDocRef) { return ref.get(); }
  set(ref: InMemoryDocRef, data: Doc) { this.writes.push({ type: 'set', ref, data }); }
  update(ref: InMemoryDocRef, data: Partial<Doc>) { this.writes.push({ type: 'update', ref, data }); }
  delete(ref: InMemoryDocRef) { this.writes.push({ type: 'delete', ref }); }
  _commit() {
    for (const w of this.writes) {
      if (w.type === 'set') w.ref.collection._set(w.ref.id, w.data);
      else if (w.type === 'update') w.ref.collection._update(w.ref.id, w.data);
      else if (w.type === 'delete') w.ref.collection._delete(w.ref.id);
    }
  }
}

class InMemoryDB {
  private collections = new Map<string, InMemoryCollection>();
  collection(name: string): InMemoryCollection {
    if (!this.collections.has(name)) this.collections.set(name, new InMemoryCollection());
    return this.collections.get(name)!;
  }
  async runTransaction<T>(fn: (tx: InMemoryTransaction) => Promise<T>): Promise<T> {
    const tx = new InMemoryTransaction();
    const result = await fn(tx);
    tx._commit();
    return result;
  }
  batch() {
    const ops: Array<() => void> = [];
    return {
      set: (ref: InMemoryDocRef, data: Doc) => { ops.push(() => ref.collection._set(ref.id, data)); },
      update: (ref: InMemoryDocRef, data: Partial<Doc>) => { ops.push(() => ref.collection._update(ref.id, data)); },
      delete: (ref: InMemoryDocRef) => { ops.push(() => ref.collection._delete(ref.id)); },
      commit: async () => { ops.forEach(op => op()); },
    };
  }
}

function getNestedField(obj: any, path: string): any {
  return path.split('.').reduce((o, k) => o?.[k], obj);
}

export const demoDB = new InMemoryDB();

// --- Seed demo data ---
import { DEFAULT_CONFIG, DEFAULT_SERVICES } from './constants.js';

// Config
demoDB.collection('config').doc('main').set({ ...DEFAULT_CONFIG });

// Services
for (const svc of DEFAULT_SERVICES) {
  demoDB.collection('services').doc(svc.id).set(svc);
}

// Demo station
demoDB.collection('stations').doc('station-001').set({
  id: 'station-001',
  name: 'Trạm 01 - Quận 7',
  location: '123 Nguyễn Văn Linh, Q7, HCM',
  status: 'ONLINE',
  tabletId: 'tablet-001',
  esp32Status: 'ONLINE',
  lastHeartbeat: Date.now(),
  createdAt: Date.now(),
  updatedAt: Date.now(),
});

// Demo admin
demoDB.collection('admins').doc('admin').set({
  id: 'admin',
  username: 'admin',
  passwordHash: 'demo123', // plain text for demo
  name: 'Admin',
  role: 'OWNER',
  stations: ['station-001'],
  isActive: true,
  createdAt: Date.now(),
});

console.log('📦 Demo database initialized: 1 station, 6 services, 1 admin');
