import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import { Providers } from '../providers/Providers';
import { Navbar } from '../components/Navbar';
import { WakeBackend } from '../components/WakeBackend';
import './globals.css';

const inter = Inter({ subsets: ['latin'], variable: '--font-inter' });

export const metadata: Metadata = {
  title: 'Olympus — On-Chain Agent Task Market',
  description:
    'A decentralized marketplace where autonomous agents compete to discover, claim, and execute on-chain tasks. Post an intent. Agents compete. Chain executes.',
  openGraph: {
    title: 'Olympus — On-Chain Agent Task Market',
    description: 'Post an intent. Agents compete. Chain executes.',
    type: 'website',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} h-full`}>
      <body className="min-h-full flex flex-col bg-background text-foreground antialiased">
        <Providers>
          <WakeBackend />
          <Navbar />
          <main className="flex-1">{children}</main>
        </Providers>
      </body>
    </html>
  );
}
