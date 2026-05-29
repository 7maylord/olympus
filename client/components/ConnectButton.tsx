'use client';

import { usePrivy } from '@privy-io/react-auth';
import { useAccount, useBalance } from 'wagmi';
import { Wallet, LogOut, ChevronDown, Loader2 } from 'lucide-react';
import { useState, useRef, useEffect } from 'react';
import { mantleTestnet } from '../lib/chain';

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function formatStt(wei: bigint): string {
  const stt = Number(wei) / 1e18;
  return stt.toFixed(3);
}

export function ConnectButton() {
  const { login, logout, authenticated, ready } = usePrivy();
  const { address } = useAccount();
  const { data: balance } = useBalance({
    address,
    chainId: mantleTestnet.id,
    query: { enabled: !!address },
  });

  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  if (!ready) {
    return (
      <button className="btn-secondary" disabled>
        <Loader2 size={15} className="animate-spin" />
        Loading…
      </button>
    );
  }

  if (!authenticated || !address) {
    return (
      <button className="btn-primary" onClick={login} id="connect-wallet-btn">
        <Wallet size={15} />
        Connect Wallet
      </button>
    );
  }

  return (
    <div className="relative" ref={ref}>
      <button
        id="wallet-menu-btn"
        className="btn-secondary"
        onClick={() => setOpen((v) => !v)}
      >
        <span
          style={{
            width: 8,
            height: 8,
            borderRadius: '50%',
            background: 'var(--green)',
            flexShrink: 0,
            boxShadow: '0 0 6px var(--green)',
          }}
        />
        <span style={{ fontSize: '0.8rem' }}>
          {balance ? `${formatStt(balance.value)} STT` : truncate(address)}
        </span>
        <ChevronDown size={13} style={{ opacity: 0.6 }} />
      </button>

      {open && (
        <div
          className="card fade-in-up"
          style={{
            position: 'absolute',
            right: 0,
            top: 'calc(100% + 8px)',
            minWidth: 220,
            padding: '0.5rem',
            zIndex: 100,
          }}
        >
          <div style={{ padding: '0.5rem 0.75rem 0.75rem', borderBottom: '1px solid var(--border)' }}>
            <div style={{ fontSize: '0.7rem', color: 'var(--foreground-muted)', marginBottom: 2 }}>
              Connected wallet
            </div>
            <div style={{ fontFamily: 'monospace', fontSize: '0.8rem', wordBreak: 'break-all' }}>
              {address}
            </div>
            {balance && (
              <div style={{ marginTop: 6, fontSize: '0.8rem', color: 'var(--gold)', fontWeight: 600 }}>
                {formatStt(balance.value)} STT
              </div>
            )}
          </div>
          <button
            className="btn-ghost"
            style={{ width: '100%', marginTop: '0.25rem', color: 'var(--red)' }}
            onClick={() => { logout(); setOpen(false); }}
          >
            <LogOut size={14} />
            Disconnect
          </button>
        </div>
      )}
    </div>
  );
}
