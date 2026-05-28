'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ConnectButton } from './ConnectButton';
import { Zap, Menu, X } from 'lucide-react';
import { useState } from 'react';
import clsx from 'clsx';

const navLinks = [
  { href: '/', label: 'Tasks' },
  { href: '/agents', label: 'Agents' },
  { href: '/post', label: 'Post Task' },
];

export function Navbar() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header
      style={{
        background: 'rgba(5, 8, 16, 0.6)',
        backdropFilter: 'blur(24px)',
        WebkitBackdropFilter: 'blur(24px)',
        borderBottom: '1px solid rgba(99, 102, 241, 0.1)',
        position: 'sticky',
        top: 0,
        zIndex: 50,
      }}
    >
      <nav
        style={{
          maxWidth: 1280,
          margin: '0 auto',
          padding: '0 1.5rem',
          height: 64,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        {/* Logo */}
        <Link
          href="/"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.625rem',
            textDecoration: 'none',
          }}
          className="group"
        >
          <div
            style={{
              width: 36,
              height: 36,
              borderRadius: '10px',
              overflow: 'hidden',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 0 16px rgba(99,102,241,0.25)',
              border: '1px solid rgba(99,102,241,0.2)',
              transition: 'all 0.3s ease',
            }}
            className="group-hover:shadow-[0_0_24px_rgba(99,102,241,0.5)] group-hover:border-indigo-400/40"
          >
            <Image src="/logo.png" alt="Olympus Logo" width={36} height={36} priority />
          </div>
          <span
            style={{
              fontWeight: 800,
              fontSize: '1.1rem',
              letterSpacing: '-0.02em',
            }}
            className="gradient-text"
          >
            OLYMPUS
          </span>
        </Link>

        {/* Desktop nav */}
        <div
          className="desktop-nav"
          style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}
        >
          {navLinks.map((link) => {
            const active = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className={clsx('btn-ghost', active && 'active-nav')}
                style={
                  active
                    ? {
                        color: 'var(--accent)',
                        background: 'rgba(99,102,241,0.1)',
                        fontWeight: 600,
                      }
                    : {}
                }
              >
                {link.label}
              </Link>
            );
          })}
        </div>

        {/* Right side */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <ConnectButton />
          <button
            className="btn-ghost"
            style={{ display: 'none' }}
            id="mobile-menu-btn"
            onClick={() => setMobileOpen((v) => !v)}
            aria-label="Toggle menu"
          >
            {mobileOpen ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </nav>

      {/* Mobile menu */}
      {mobileOpen && (
        <div
          className="card fade-in-up"
          style={{
            margin: '0 1rem 0.5rem',
            padding: '0.5rem',
            display: 'flex',
            flexDirection: 'column',
            gap: '0.25rem',
          }}
        >
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="btn-ghost"
              style={{
                width: '100%',
                justifyContent: 'flex-start',
                color: pathname === link.href ? 'var(--accent)' : undefined,
              }}
              onClick={() => setMobileOpen(false)}
            >
              {link.label}
            </Link>
          ))}
        </div>
      )}
    </header>
  );
}
