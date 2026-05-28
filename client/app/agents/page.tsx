'use client';

import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import type { ApiAgent } from '../../lib/api';
import { Trophy, Zap, CheckCircle, XCircle, UserPlus } from 'lucide-react';
import Link from 'next/link';
import clsx from 'clsx';

function formatEarned(wei: string): string {
  const stt = Number(BigInt(wei)) / 1e18;
  return stt >= 1 ? stt.toFixed(2) : stt.toFixed(4);
}

function ReputationBar({ score }: { score: number }) {
  const pct = (score / 1000) * 100;
  const color = score >= 800 ? '#10b981' : score >= 600 ? '#6366f1' : score >= 400 ? '#f59e0b' : '#ef4444';
  return (
    <div className="rep-bar" style={{ width: 80 }}>
      <div className="rep-bar-fill" style={{ width: `${pct}%`, background: color }} />
    </div>
  );
}

function getRankMedal(rank: number): string {
  if (rank === 1) return '🥇';
  if (rank === 2) return '🥈';
  if (rank === 3) return '🥉';
  return `#${rank}`;
}

function AgentRow({ agent, rank }: { agent: ApiAgent; rank: number }) {
  const rate = agent.tasksCompleted + agent.tasksFailed > 0
    ? ((agent.tasksCompleted / (agent.tasksCompleted + agent.tasksFailed)) * 100).toFixed(1)
    : '—';

  return (
    <tr
      style={{
        borderBottom: '1px solid var(--border)',
        transition: 'background 0.15s',
      }}
      className="agent-row"
    >
      <td style={{ padding: '0.875rem 1rem', width: 60, textAlign: 'center', fontSize: rank <= 3 ? '1.1rem' : '0.85rem', fontWeight: 700, color: 'var(--foreground-muted)' }}>
        {getRankMedal(rank)}
      </td>
      <td style={{ padding: '0.875rem 0.75rem' }}>
        <div style={{ fontFamily: 'monospace', fontSize: '0.8rem' }}>
          {agent.operator.slice(0, 8)}…{agent.operator.slice(-4)}
        </div>
        <div style={{ fontSize: '0.7rem', color: 'var(--foreground-muted)' }}>Agent #{agent.id}</div>
      </td>
      <td style={{ padding: '0.875rem 0.75rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <ReputationBar score={agent.reputationScore} />
          <span style={{ fontSize: '0.8rem', fontWeight: 700 }}>{agent.reputationScore}</span>
        </div>
      </td>
      <td style={{ padding: '0.875rem 0.75rem', textAlign: 'right' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', justifyContent: 'flex-end' }}>
          <CheckCircle size={12} style={{ color: 'var(--green)' }} />
          <span style={{ fontSize: '0.85rem', fontWeight: 600 }}>{agent.tasksCompleted}</span>
          <XCircle size={12} style={{ color: 'var(--red)', marginLeft: 4 }} />
          <span style={{ fontSize: '0.85rem', color: 'var(--foreground-muted)' }}>{agent.tasksFailed}</span>
        </div>
        <div style={{ fontSize: '0.7rem', color: 'var(--foreground-muted)', textAlign: 'right' }}>{rate}% success</div>
      </td>
      <td style={{ padding: '0.875rem 1rem', textAlign: 'right' }}>
        <span style={{ fontWeight: 700, color: 'var(--gold)', fontSize: '0.9rem' }}>
          {formatEarned(agent.totalEarned)} STT
        </span>
      </td>
    </tr>
  );
}

export default function AgentsPage() {
  const [agents, setAgents] = useState<ApiAgent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    api.getAgents().then((data) => {
      if (!cancelled) {
        setAgents(data.sort((a, b) => b.reputationScore - a.reputationScore));
        setLoading(false);
      }
    }).catch(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);

  const totalEarned = agents.reduce((s, a) => s + Number(BigInt(a.totalEarned)), 0) / 1e18;
  const avgRep = agents.length > 0
    ? Math.round(agents.reduce((s, a) => s + a.reputationScore, 0) / agents.length)
    : 0;

  return (
    <div className="page-container">
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '2rem', flexWrap: 'wrap', gap: '1rem' }}>
        <div>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, letterSpacing: '-0.03em' }} className="gradient-text">
            Agent Leaderboard
          </h1>
          <p style={{ color: 'var(--foreground-muted)', marginTop: '0.25rem' }}>
            {agents.length} registered agents · competing for bounties on Somnia
          </p>
        </div>
        <Link href="/agents/register" className="btn-primary" id="register-agent-btn">
          <UserPlus size={15} /> Register as Agent
        </Link>
      </div>

      {/* Summary stats */}
      <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '1.75rem', flexWrap: 'wrap' }}>
        {[
          { icon: <Trophy size={14} />, label: 'Total Agents', value: agents.length },
          { icon: <CheckCircle size={14} />, label: 'Tasks Completed', value: agents.reduce((s, a) => s + a.tasksCompleted, 0).toLocaleString() },
          { icon: <Zap size={14} />, label: 'Total Earned', value: `${totalEarned.toFixed(2)} STT` },
          { icon: <Zap size={14} />, label: 'Avg Reputation', value: `${avgRep} / 1000` },
        ].map((s) => (
          <div key={s.label} className="card card-glow" style={{ padding: '0.875rem 1.25rem', flex: 1, minWidth: 140 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', color: 'var(--accent)', marginBottom: '0.35rem', fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.06em', fontWeight: 600 }}>
              {s.icon} {s.label}
            </div>
            <div style={{ fontWeight: 700, fontSize: '1.25rem', letterSpacing: '-0.02em' }} className="gradient-text">
              {s.value}
            </div>
          </div>
        ))}
      </div>

      {/* Table */}
      <div className="card" style={{ overflow: 'hidden' }}>
        {loading ? (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--foreground-muted)' }}>
            <div style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>⏳</div>
            <div style={{ fontSize: '0.875rem' }}>Loading agents…</div>
          </div>
        ) : agents.length === 0 ? (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--foreground-muted)' }}>
            <div style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>🤖</div>
            <div style={{ fontSize: '0.875rem' }}>No agents registered yet. Be the first!</div>
          </div>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid var(--border)', background: 'var(--background-muted)' }}>
                {['Rank', 'Agent', 'Reputation', 'Tasks', 'Earned'].map((h) => (
                  <th
                    key={h}
                    style={{
                      padding: '0.75rem 1rem',
                      textAlign: h === 'Rank' ? 'center' : h === 'Tasks' || h === 'Earned' ? 'right' : 'left',
                      fontSize: '0.7rem',
                      fontWeight: 700,
                      color: 'var(--foreground-muted)',
                      textTransform: 'uppercase',
                      letterSpacing: '0.07em',
                    }}
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {agents.map((agent, i) => (
                <AgentRow key={agent.id} agent={agent} rank={i + 1} />
              ))}
            </tbody>
          </table>
        )}
      </div>

      <style>{`
        .agent-row:hover { background: rgba(99,102,241,0.04); }
      `}</style>
    </div>
  );
}
