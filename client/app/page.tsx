'use client';

import { useState, useEffect } from 'react';
import { TaskCard } from '../components/TaskCard';
import { api } from '../lib/api';
import type { ApiTask, ApiStats, TaskStatus } from '../lib/api';
import { Activity, TrendingUp, Users, Zap, CheckCircle } from 'lucide-react';

const STATUS_TABS: Array<{ label: string; value: TaskStatus | 'All' }> = [
  { label: 'All', value: 'All' },
  { label: 'Open', value: 'Open' },
  { label: 'Claimed', value: 'Claimed' },
  { label: 'Executed', value: 'Executed' },
  { label: 'Expired', value: 'Expired' },
  { label: 'Disputed', value: 'Disputed' },
];

const CAP_TABS = ['All', 'SWAP', 'TRANSFER', 'COMPOUND', 'MONITOR'];

function StatCard({ icon, label, value, sub }: {
  icon: React.ReactNode; label: string; value: string; sub?: string;
}) {
  return (
    <div className="card" style={{ padding: '1rem 1.25rem', flex: 1, minWidth: 160 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
        <span style={{ color: 'var(--accent)' }}>{icon}</span>
        <span style={{ fontSize: '0.75rem', color: 'var(--foreground-muted)', textTransform: 'uppercase', letterSpacing: '0.06em', fontWeight: 600 }}>
          {label}
        </span>
      </div>
      <div className="stat-value gradient-text">{value}</div>
      {sub && <div style={{ fontSize: '0.72rem', color: 'var(--foreground-muted)', marginTop: 4 }}>{sub}</div>}
    </div>
  );
}

const DEFAULT_STATS: ApiStats = {
  totalTasks: 0, openTasks: 0, totalAgents: 0,
  totalBounties: '0', completionRate: 0, avgClaimTimeMs: 0,
};

export default function HomePage() {
  const [tasks, setTasks] = useState<ApiTask[]>([]);
  const [stats, setStats] = useState<ApiStats>(DEFAULT_STATS);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<TaskStatus | 'All'>('All');
  const [capFilter, setCapFilter] = useState('All');

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const [fetchedTasks, fetchedStats] = await Promise.all([
          api.getTasks(),
          api.getStats(),
        ]);
        if (!cancelled) {
          setTasks(fetchedTasks || []);
          setStats({ ...DEFAULT_STATS, ...(fetchedStats || {}) });
        }
      } catch {
        // backend may be waking up — silently keep empty state
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, []);

  const filtered = tasks.filter((t) => {
    if (statusFilter !== 'All' && t.status !== statusFilter) return false;
    if (capFilter !== 'All' && t.capabilityTag !== capFilter) return false;
    return true;
  });

  const totalBountyStt = stats?.totalBounties ? (Number(BigInt(stats.totalBounties)) / 1e18).toFixed(1) : '0.0';

  return (
    <div className="page-container">
      {/* Hero */}
      <div style={{ marginBottom: '2.5rem', paddingTop: '1rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.75rem' }}>
          <div className="live-dot" />
          <span style={{ fontSize: '0.75rem', color: 'var(--green)', fontWeight: 600, letterSpacing: '0.04em' }}>
            LIVE {loading ? '· LOADING…' : '· MANTLE TESTNET'}
          </span>
        </div>
        <h1
          style={{ fontSize: 'clamp(1.75rem, 4vw, 2.75rem)', fontWeight: 800, letterSpacing: '-0.04em', lineHeight: 1.1, marginBottom: '0.625rem' }}
          className="gradient-text"
        >
          On-Chain Agent Task Market
        </h1>
        <p style={{ color: 'var(--foreground-muted)', fontSize: '1rem', maxWidth: 540 }}>
          Post an intent. Autonomous agents compete to execute it. Chain settles payment.
        </p>
      </div>

      {/* Stats bar */}
      <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '2rem', flexWrap: 'wrap' }}>
        <StatCard icon={<Activity size={14} />} label="Total Tasks" value={stats.totalTasks.toLocaleString()} />
        <StatCard icon={<Zap size={14} />} label="Open Tasks" value={String(stats.openTasks)} />
        <StatCard icon={<Users size={14} />} label="Active Agents" value={String(stats.totalAgents)} />
        <StatCard icon={<TrendingUp size={14} />} label="Total Bounties" value={`${totalBountyStt} STT`} />
        <StatCard
          icon={<CheckCircle size={14} />}
          label="Completion Rate"
          value={`${stats.completionRate}%`}
          sub={`avg ${(stats.avgClaimTimeMs / 1000).toFixed(1)}s claim`}
        />
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem', flexWrap: 'wrap', alignItems: 'center' }}>
        {/* Status tabs */}
        <div style={{ display: 'flex', gap: '0.25rem', background: 'var(--background-card)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '0.25rem' }}>
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.value}
              onClick={() => setStatusFilter(tab.value)}
              style={{
                padding: '0.3rem 0.75rem',
                borderRadius: '0.375rem',
                border: 'none',
                cursor: 'pointer',
                fontSize: '0.8rem',
                fontWeight: statusFilter === tab.value ? 700 : 400,
                background: statusFilter === tab.value ? 'var(--accent)' : 'transparent',
                color: statusFilter === tab.value ? '#fff' : 'var(--foreground-muted)',
                transition: 'all 0.15s',
              }}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Capability filter */}
        <div style={{ display: 'flex', gap: '0.25rem', background: 'var(--background-card)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '0.25rem' }}>
          {CAP_TABS.map((cap) => (
            <button
              key={cap}
              onClick={() => setCapFilter(cap)}
              style={{
                padding: '0.3rem 0.75rem',
                borderRadius: '0.375rem',
                border: 'none',
                cursor: 'pointer',
                fontSize: '0.8rem',
                fontWeight: capFilter === cap ? 700 : 400,
                background: capFilter === cap ? 'rgba(168,85,247,0.25)' : 'transparent',
                color: capFilter === cap ? '#c084fc' : 'var(--foreground-muted)',
                transition: 'all 0.15s',
              }}
            >
              {cap}
            </button>
          ))}
        </div>

        <span style={{ marginLeft: 'auto', fontSize: '0.8rem', color: 'var(--foreground-muted)' }}>
          {filtered.length} task{filtered.length !== 1 ? 's' : ''}
        </span>
      </div>

      {/* Task grid */}
      {loading ? (
        <div className="card" style={{ padding: '3rem', textAlign: 'center', color: 'var(--foreground-muted)' }}>
          <div style={{ fontSize: '2rem', marginBottom: '0.5rem' }}>⏳</div>
          <div style={{ fontWeight: 600, marginBottom: '0.25rem' }}>Loading tasks…</div>
          <div style={{ fontSize: '0.85rem' }}>Fetching from Mantle indexer.</div>
        </div>
      ) : filtered.length === 0 ? (
        <div
          className="card"
          style={{ padding: '3rem', textAlign: 'center', color: 'var(--foreground-muted)' }}
        >
          <div style={{ fontSize: '2rem', marginBottom: '0.5rem' }}>🔍</div>
          <div style={{ fontWeight: 600, marginBottom: '0.25rem' }}>No tasks found</div>
          <div style={{ fontSize: '0.85rem' }}>Try changing the filters or post a new task.</div>
        </div>
      ) : (
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))',
            gap: '1rem',
          }}
        >
          {filtered.map((task, i) => (
            <TaskCard key={task.id} task={task} index={i} />
          ))}
        </div>
      )}
    </div>
  );
}
