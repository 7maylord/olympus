import Link from 'next/link';
import { ArrowRight, Clock, User, Zap } from 'lucide-react';
import type { ApiTask } from '../lib/api';
import clsx from 'clsx';

function formatBounty(wei: string): string {
  const stt = Number(BigInt(wei)) / 1e18;
  return stt < 0.001 ? stt.toExponential(2) : stt.toFixed(4);
}

function formatExpiry(expiry: string): string {
  const ms = Number(expiry) * 1000 - Date.now();
  if (ms <= 0) return 'Expired';
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  if (h > 48) return `${Math.floor(h / 24)}d left`;
  if (h > 0) return `${h}h ${m}m left`;
  return `${m}m left`;
}

function getCapLabel(tag: string): string {
  const map: Record<string, string> = {
    SWAP: '⇄ Swap',
    TRANSFER: '→ Transfer',
    COMPOUND: '↺ Compound',
    MONITOR: '◎ Monitor',
  };
  return map[tag] ?? tag;
}

interface Props {
  task: ApiTask;
  index?: number;
}

export function TaskCard({ task, index = 0 }: Props) {
  const statusClass = `badge-${task.status.toLowerCase()}`;
  const expiryStr = formatExpiry(task.expiry);
  const expiringSoon = Number(task.expiry) * 1000 - Date.now() < 3_600_000;

  return (
    <Link
      href={`/tasks/${task.id}`}
      className="card fade-in-up"
      style={{
        display: 'block',
        padding: '1.25rem',
        textDecoration: 'none',
        animationDelay: `${index * 60}ms`,
        animationFillMode: 'both',
      }}
      id={`task-card-${task.id}`}
    >
      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '0.75rem', marginBottom: '0.875rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
          <span className={clsx('badge', 'badge-cap')}>{getCapLabel(task.capabilityTag)}</span>
          <span className={clsx('badge', statusClass)}>
            {task.status === 'Open' && <div className="live-dot" style={{ width: 6, height: 6, marginRight: 4 }} />}
            {task.status}
          </span>
        </div>
        {/* Bounty */}
        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <div
            style={{
              fontWeight: 700,
              fontSize: '1.1rem',
              color: 'var(--gold)',
              letterSpacing: '-0.02em',
              textShadow: '0 0 12px var(--gold-glow)',
            }}
          >
            {formatBounty(task.bounty)} STT
          </div>
        </div>
      </div>

      {/* Task ID */}
      <div style={{ fontSize: '0.7rem', color: 'var(--foreground-subtle)', fontFamily: 'monospace', marginBottom: '0.75rem' }}>
        Task #{task.id}
      </div>

      {/* Footer row */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '0.5rem',
          paddingTop: '0.75rem',
          borderTop: '1px solid var(--border)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          {/* Poster */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', fontSize: '0.75rem', color: 'var(--foreground-muted)' }}>
            <User size={12} />
            <span style={{ fontFamily: 'monospace' }}>
              {task.poster.slice(0, 6)}…{task.poster.slice(-4)}
            </span>
          </div>
          {/* Expiry */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.35rem',
              fontSize: '0.75rem',
              color: expiringSoon ? 'var(--red)' : 'var(--foreground-muted)',
              marginLeft: '0.75rem',
            }}
          >
            <Clock size={12} />
            <span>{expiryStr}</span>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem', fontSize: '0.75rem', color: 'var(--accent)' }}>
          View <ArrowRight size={12} />
        </div>
      </div>

      {/* Claimed by */}
      {task.claimedBy && (
        <div
          style={{
            marginTop: '0.625rem',
            padding: '0.375rem 0.625rem',
            background: 'rgba(245,158,11,0.07)',
            borderRadius: '0.375rem',
            fontSize: '0.72rem',
            color: 'var(--amber)',
            display: 'flex',
            alignItems: 'center',
            gap: '0.4rem',
          }}
        >
          <Zap size={11} />
          Claimed by {task.claimedBy.slice(0, 8)}…{task.claimedBy.slice(-4)}
        </div>
      )}
    </Link>
  );
}
