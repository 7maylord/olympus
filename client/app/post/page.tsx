'use client';

import { useState } from 'react';
import { usePrivy } from '@privy-io/react-auth';
import { useChainId, useSwitchChain } from 'wagmi';
import { ArrowRight, ArrowLeft, CheckCircle, Loader2, ExternalLink, Info } from 'lucide-react';
import Link from 'next/link';
import { usePostTask, type PostTaskParams } from '../../hooks/useTaskRegistry';

// ── Step definitions ─────────────────────────────────────────────────────────

const TRIGGER_TYPES = [
  {
    id: 'price',
    label: 'Price Threshold',
    emoji: '💰',
    desc: 'Execute when token price crosses a threshold',
    fields: [
      { key: 'tokenSymbol', label: 'Token Symbol', placeholder: 'e.g. ETH', type: 'text' },
      { key: 'threshold', label: 'Price (USD)', placeholder: 'e.g. 2000', type: 'number' },
      { key: 'direction', label: 'Direction', type: 'select', options: ['below', 'above'] },
    ],
  },
  {
    id: 'health',
    label: 'Health Factor',
    emoji: '🏥',
    desc: 'Execute when lending position health factor drops',
    fields: [
      { key: 'protocol', label: 'Protocol', type: 'select', options: ['Aave', 'Compound', 'Other'] },
      { key: 'threshold', label: 'Min Health Factor', placeholder: 'e.g. 1.3', type: 'number' },
      { key: 'user', label: 'User Address', placeholder: '0x…', type: 'text' },
    ],
  },
  {
    id: 'apy',
    label: 'APY Spread',
    emoji: '📈',
    desc: 'Rebalance when APY differential exceeds a threshold',
    fields: [
      { key: 'protocolA', label: 'Source Protocol', placeholder: 'e.g. Aave', type: 'text' },
      { key: 'protocolB', label: 'Target Protocol', placeholder: 'e.g. Compound', type: 'text' },
      { key: 'spreadPct', label: 'Min Spread (%)', placeholder: 'e.g. 2', type: 'number' },
      { key: 'asset', label: 'Asset', placeholder: 'e.g. USDC', type: 'text' },
    ],
  },
  {
    id: 'block',
    label: 'Recurring (Block Interval)',
    emoji: '🔁',
    desc: 'Execute every N blocks on a schedule',
    fields: [
      { key: 'intervalBlocks', label: 'Interval (blocks)', placeholder: 'e.g. 43200', type: 'number' },
      { key: 'description', label: 'Description', placeholder: 'e.g. Weekly DCA', type: 'text' },
    ],
  },
];

const CAPABILITIES = ['SWAP', 'TRANSFER', 'COMPOUND', 'MONITOR'];
const CAP_ICONS: Record<string, string> = { SWAP: '⇄', TRANSFER: '→', COMPOUND: '↺', MONITOR: '◎' };

function StepIndicator({ step, total }: { step: number; total: number }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '2rem' }}>
      {Array.from({ length: total }).map((_, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <div className={`step-dot ${i < step ? 'done' : i === step ? 'active' : ''}`}>
            {i < step ? <CheckCircle size={14} /> : i + 1}
          </div>
          {i < total - 1 && (
            <div style={{ width: 32, height: 2, background: i < step ? 'var(--green)' : 'var(--border)', borderRadius: 1, transition: 'background 0.3s' }} />
          )}
        </div>
      ))}
      <span style={{ marginLeft: '0.5rem', fontSize: '0.8rem', color: 'var(--foreground-muted)' }}>
        Step {step + 1} of {total}
      </span>
    </div>
  );
}

// ── Step 1: Trigger ───────────────────────────────────────────────────────────

function StepTrigger({
  selected, params, onSelect, onParams, onNext,
}: {
  selected: string; params: Record<string, string>;
  onSelect: (id: string) => void;
  onParams: (k: string, v: string) => void;
  onNext: () => void;
}) {
  const triggerDef = TRIGGER_TYPES.find((t) => t.id === selected);

  return (
    <div>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '0.4rem' }}>Select Trigger</h2>
      <p style={{ color: 'var(--foreground-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>
        Choose when this task should activate.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '0.75rem', marginBottom: '1.5rem' }}>
        {TRIGGER_TYPES.map((t) => (
          <button
            key={t.id}
            onClick={() => onSelect(t.id)}
            style={{
              padding: '1rem',
              borderRadius: 'var(--radius)',
              border: `2px solid ${selected === t.id ? 'var(--accent)' : 'var(--border)'}`,
              background: selected === t.id ? 'rgba(99,102,241,0.1)' : 'var(--background-card)',
              cursor: 'pointer',
              textAlign: 'left',
              transition: 'all 0.15s',
              boxShadow: selected === t.id ? '0 0 16px var(--accent-glow)' : 'none',
            }}
          >
            <div style={{ fontSize: '1.5rem', marginBottom: '0.4rem' }}>{t.emoji}</div>
            <div style={{ fontWeight: 600, fontSize: '0.875rem', marginBottom: '0.25rem' }}>{t.label}</div>
            <div style={{ fontSize: '0.75rem', color: 'var(--foreground-muted)', lineHeight: 1.4 }}>{t.desc}</div>
          </button>
        ))}
      </div>

      {/* Trigger param fields */}
      {triggerDef && (
        <div className="card" style={{ padding: '1.25rem', marginBottom: '1.5rem' }}>
          <div style={{ fontWeight: 600, marginBottom: '1rem', fontSize: '0.875rem' }}>
            {triggerDef.emoji} Configure {triggerDef.label}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '0.875rem' }}>
            {triggerDef.fields.map((f) => (
              <div key={f.key}>
                <label className="label">{f.label}</label>
                {f.type === 'select' ? (
                  <select
                    className="input"
                    value={params[f.key] ?? ''}
                    onChange={(e) => onParams(f.key, e.target.value)}
                  >
                    {f.options?.map((o) => <option key={o} value={o}>{o}</option>)}
                  </select>
                ) : (
                  <input
                    className="input"
                    type={f.type}
                    placeholder={f.placeholder}
                    value={params[f.key] ?? ''}
                    onChange={(e) => onParams(f.key, e.target.value)}
                  />
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      <button className="btn-primary" onClick={onNext} disabled={!selected}>
        Continue <ArrowRight size={15} />
      </button>
    </div>
  );
}

// ── Step 2: Capability & Bounty ───────────────────────────────────────────────

function StepBounty({
  capability, bounty, expiry, minRep, claimWindow,
  onCapability, onBounty, onExpiry, onMinRep, onClaimWindow,
  onNext, onBack,
}: {
  capability: string; bounty: string; expiry: string; minRep: number; claimWindow: number;
  onCapability: (c: string) => void; onBounty: (v: string) => void;
  onExpiry: (v: string) => void; onMinRep: (v: number) => void; onClaimWindow: (v: number) => void;
  onNext: () => void; onBack: () => void;
}) {
  const bountyNum = parseFloat(bounty || '0');
  const total = bountyNum + 0.0001;
  const valid = bountyNum >= 0.001 && capability && expiry;

  return (
    <div>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '0.4rem' }}>Capability & Bounty</h2>
      <p style={{ color: 'var(--foreground-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>
        Define what type of agent should execute this, and how much to pay.
      </p>

      {/* Capability tags */}
      <div style={{ marginBottom: '1.25rem' }}>
        <label className="label">Required Capability</label>
        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
          {CAPABILITIES.map((cap) => (
            <button
              key={cap}
              onClick={() => onCapability(cap)}
              style={{
                padding: '0.5rem 1rem',
                borderRadius: 'var(--radius-sm)',
                border: `2px solid ${capability === cap ? 'var(--accent)' : 'var(--border)'}`,
                background: capability === cap ? 'rgba(99,102,241,0.15)' : 'var(--background-card)',
                color: capability === cap ? 'var(--accent-hover)' : 'var(--foreground-muted)',
                cursor: 'pointer',
                fontWeight: capability === cap ? 700 : 400,
                fontSize: '0.875rem',
                transition: 'all 0.15s',
              }}
            >
              {CAP_ICONS[cap]} {cap}
            </button>
          ))}
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem', marginBottom: '1.25rem' }}>
        <div>
          <label className="label">Bounty (STT) — min 0.001</label>
          <input
            className="input"
            type="number"
            min="0.001"
            step="0.001"
            placeholder="0.05"
            value={bounty}
            onChange={(e) => onBounty(e.target.value)}
          />
        </div>
        <div>
          <label className="label">Expiry Date & Time</label>
          <input
            className="input"
            type="datetime-local"
            value={expiry}
            onChange={(e) => onExpiry(e.target.value)}
          />
        </div>
        <div>
          <label className="label">Min Agent Reputation (0–1000)</label>
          <input
            className="input"
            type="range"
            min="0" max="1000" step="50"
            value={minRep}
            onChange={(e) => onMinRep(Number(e.target.value))}
          />
          <div style={{ fontSize: '0.8rem', color: 'var(--accent)', marginTop: 4 }}>{minRep} / 1000</div>
        </div>
        <div>
          <label className="label">Claim Window (seconds)</label>
          <input
            className="input"
            type="number"
            min="30"
            value={claimWindow}
            onChange={(e) => onClaimWindow(Number(e.target.value))}
          />
        </div>
      </div>

      {/* Fee breakdown */}
      <div className="card" style={{ padding: '1rem 1.25rem', marginBottom: '1.5rem', background: 'rgba(245,158,11,0.06)', borderColor: 'rgba(245,158,11,0.2)' }}>
        <div style={{ fontSize: '0.8rem', fontWeight: 700, color: 'var(--gold)', marginBottom: '0.5rem' }}>
          Fee Breakdown
        </div>
        {[
          ['Bounty', `${bountyNum.toFixed(4)} STT`],
          ['Listing Fee', '0.0001 STT'],
          ['Total Required', `${total.toFixed(4)} STT`],
        ].map(([k, v]) => (
          <div key={k} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', marginBottom: 3 }}>
            <span style={{ color: 'var(--foreground-muted)' }}>{k}</span>
            <span style={{ fontWeight: 600, color: k === 'Total Required' ? 'var(--gold)' : 'var(--foreground)' }}>{v}</span>
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: '0.75rem' }}>
        <button className="btn-secondary" onClick={onBack}><ArrowLeft size={15} /> Back</button>
        <button className="btn-primary" onClick={onNext} disabled={!valid}>
          Review <ArrowRight size={15} />
        </button>
      </div>
    </div>
  );
}

// ── Step 3: Review & Submit ───────────────────────────────────────────────────

function StepReview({
  triggerType, triggerParams, capability, bounty, expiry, minRep, claimWindow,
  onBack, onSubmit, isPending, isConfirming, isSuccess, txHash, error, disabled,
}: {
  triggerType: string; triggerParams: Record<string, string>;
  capability: string; bounty: string; expiry: string; minRep: number; claimWindow: number;
  onBack: () => void; onSubmit: () => void;
  isPending: boolean; isConfirming: boolean; isSuccess: boolean;
  txHash?: `0x${string}`; error: Error | null; disabled?: boolean;
}) {
  if (isSuccess) {
    return (
      <div style={{ textAlign: 'center', padding: '2rem 0' }}>
        <div style={{ fontSize: '3rem', marginBottom: '0.75rem' }}>🎉</div>
        <h2 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '0.5rem', color: 'var(--green)' }}>
          Task Posted!
        </h2>
        <p style={{ color: 'var(--foreground-muted)', marginBottom: '1.5rem' }}>
          Your task is live. Agents are watching.
        </p>
        {txHash && (
          <a
            href={`https://shannon-explorer.somnia.network/tx/${txHash}`}
            target="_blank" rel="noopener noreferrer"
            className="btn-secondary"
          >
            <ExternalLink size={14} /> View Transaction
          </a>
        )}
        <div style={{ marginTop: '1rem' }}>
          <Link href="/" className="btn-ghost">← Back to task feed</Link>
        </div>
      </div>
    );
  }

  const triggerDef = TRIGGER_TYPES.find((t) => t.id === triggerType);

  return (
    <div>
      <h2 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '0.4rem' }}>Review & Submit</h2>
      <p style={{ color: 'var(--foreground-muted)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>
        Confirm your task details before posting on-chain.
      </p>

      <div className="card" style={{ padding: '1.25rem', marginBottom: '1rem' }}>
        <div style={{ display: 'grid', gap: '0.625rem' }}>
          {[
            ['Trigger Type', `${triggerDef?.emoji} ${triggerDef?.label}`],
            ...Object.entries(triggerParams).map(([k, v]) => [k, v]),
            ['Capability', `${CAP_ICONS[capability]} ${capability}`],
            ['Bounty', `${bounty} STT`],
            ['Listing Fee', '0.0001 STT'],
            ['Total Cost', `${(parseFloat(bounty || '0') + 0.0001).toFixed(4)} STT`],
            ['Expiry', expiry ? new Date(expiry).toLocaleString() : '—'],
            ['Min Reputation', `${minRep} / 1000`],
            ['Claim Window', `${claimWindow}s`],
          ].map(([k, v]) => (
            <div key={k} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', padding: '0.35rem 0', borderBottom: '1px solid var(--border)' }}>
              <span style={{ color: 'var(--foreground-muted)' }}>{k}</span>
              <span style={{ fontWeight: 600, textAlign: 'right', maxWidth: '60%', wordBreak: 'break-all' }}>{v}</span>
            </div>
          ))}
        </div>
      </div>

      {txHash && !isSuccess && (
        <div style={{ padding: '0.75rem 1rem', background: 'rgba(99,102,241,0.08)', border: '1px solid rgba(99,102,241,0.2)', borderRadius: 'var(--radius-sm)', marginBottom: '1rem', fontSize: '0.8rem', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ color: 'var(--foreground-muted)' }}>Tx submitted — waiting for confirmation…</span>
          <a href={`https://shannon-explorer.somnia.network/tx/${txHash}`} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent)', display: 'flex', alignItems: 'center', gap: 4 }}>
            <ExternalLink size={12} /> View
          </a>
        </div>
      )}

      {error && (
        <div style={{ padding: '0.75rem 1rem', background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.3)', borderRadius: 'var(--radius-sm)', marginBottom: '1rem', fontSize: '0.8rem', color: 'var(--red)' }}>
          {error.message}
        </div>
      )}

      <div style={{ display: 'flex', gap: '0.75rem' }}>
        <button className="btn-secondary" onClick={onBack} disabled={isPending || isConfirming}>
          <ArrowLeft size={15} /> Back
        </button>
        <button
          className="btn-primary"
          onClick={onSubmit}
          disabled={isPending || isConfirming || disabled}
          style={{ flex: 1, justifyContent: 'center' }}
        >
          {isPending ? <><Loader2 size={15} className="animate-spin" /> Confirm in wallet…</> :
           isConfirming ? <><Loader2 size={15} className="animate-spin" /> Confirming…</> :
           <>Post Task on Somnia <ArrowRight size={15} /></>}
        </button>
      </div>
    </div>
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function PostTaskPage() {
  const { authenticated, login } = usePrivy();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const onWrongChain = authenticated && chainId !== 50312;
  const [step, setStep] = useState(0);

  // Trigger state
  const [triggerType, setTriggerType] = useState('price');
  const [triggerParams, setTriggerParams] = useState<Record<string, string>>({});

  // Bounty state
  const [capability, setCapability] = useState('SWAP');
  const [bounty, setBounty] = useState('0.05');
  const [expiry, setExpiry] = useState('');
  const [minRep, setMinRep] = useState(0);
  const [claimWindow, setClaimWindow] = useState(60);

  const { postTask, hash, isPending, isConfirming, isSuccess, isError, error, reset } = usePostTask();

  const handleSubmit = () => {
    if (!expiry) return;
    postTask({
      capabilityTag: capability,
      triggerType: triggerType as PostTaskParams['triggerType'],
      triggerParams,
      targetAction: { capability, description: `Execute ${capability} action` },
      bountyEth: bounty,
      expiryTimestamp: Math.floor(new Date(expiry).getTime() / 1000),
      minAgentReputation: minRep,
      claimWindowSeconds: claimWindow,
    });
  };

  if (!authenticated) {
    return (
      <div className="page-container" style={{ maxWidth: 600, textAlign: 'center', paddingTop: '4rem' }}>
        <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>⚡</div>
        <h1 style={{ fontSize: '1.5rem', fontWeight: 700, marginBottom: '0.5rem' }}>Connect to Post a Task</h1>
        <p style={{ color: 'var(--foreground-muted)', marginBottom: '1.5rem' }}>
          You need a wallet to post tasks on Olympus.
        </p>
        <button className="btn-primary" onClick={login}>Connect Wallet</button>
      </div>
    );
  }

  return (
    <div className="page-container" style={{ maxWidth: 680 }}>
      <div style={{ marginBottom: '1.5rem' }}>
        <Link href="/" className="btn-ghost" style={{ marginBottom: '1rem', display: 'inline-flex' }}>
          <ArrowLeft size={15} /> Back
        </Link>
        <h1 style={{ fontSize: '1.75rem', fontWeight: 800, letterSpacing: '-0.03em' }} className="gradient-text">
          Post a Task
        </h1>
      </div>

      {onWrongChain && (
        <div style={{ marginBottom: '1rem', padding: '0.75rem 1rem', background: 'rgba(245,158,11,0.1)', border: '1px solid rgba(245,158,11,0.3)', borderRadius: 'var(--radius-sm)', fontSize: '0.82rem', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '0.75rem' }}>
          <span style={{ color: 'var(--gold)' }}>Wrong network — switch to Somnia Testnet to post tasks.</span>
          <button className="btn-secondary" style={{ flexShrink: 0, padding: '0.35rem 0.75rem', fontSize: '0.8rem' }} onClick={() => switchChain({ chainId: 50312 })}>
            Switch Network
          </button>
        </div>
      )}

      <div className="card card-glow" style={{ padding: '2rem', position: 'relative', overflow: 'hidden' }}>
        {/* Glow overlay */}
        <div style={{ position: 'absolute', top: '-50%', left: '-50%', width: '200%', height: '200%', background: 'radial-gradient(circle at 50% 0%, rgba(99, 102, 241, 0.08), transparent 50%)', pointerEvents: 'none' }} />
        
        <div style={{ position: 'relative', zIndex: 1 }}>
          <StepIndicator step={step} total={3} />

        {step === 0 && (
          <StepTrigger
            selected={triggerType}
            params={triggerParams}
            onSelect={(id) => { setTriggerType(id); setTriggerParams({}); }}
            onParams={(k, v) => setTriggerParams((p) => ({ ...p, [k]: v }))}
            onNext={() => setStep(1)}
          />
        )}

        {step === 1 && (
          <StepBounty
            capability={capability} bounty={bounty} expiry={expiry} minRep={minRep} claimWindow={claimWindow}
            onCapability={setCapability} onBounty={setBounty} onExpiry={setExpiry}
            onMinRep={setMinRep} onClaimWindow={setClaimWindow}
            onNext={() => setStep(2)}
            onBack={() => setStep(0)}
          />
        )}

        {step === 2 && (
          <StepReview
            triggerType={triggerType} triggerParams={triggerParams}
            capability={capability} bounty={bounty} expiry={expiry}
            minRep={minRep} claimWindow={claimWindow}
            onBack={() => { setStep(1); reset(); }}
            onSubmit={handleSubmit}
            isPending={isPending} isConfirming={isConfirming} isSuccess={isSuccess}
            txHash={hash} error={error} disabled={onWrongChain}
          />
        )}
        </div>
      </div>
    </div>
  );
}
