'use client';

import { useEffect } from 'react';

export function WakeBackend() {
  useEffect(() => {
    fetch(`${process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000'}/api/health`, {
      method: 'GET',
      cache: 'no-store',
    }).catch(() => {
      // Silently ignore — the point is just to wake Render from sleep
    });
  }, []);

  return null;
}
