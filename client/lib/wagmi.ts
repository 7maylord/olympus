import { http, createConfig } from 'wagmi';
import { somniaTestnet } from './chain';

export const wagmiConfig = createConfig({
  chains: [somniaTestnet],
  transports: {
    [somniaTestnet.id]: http(
      process.env.NEXT_PUBLIC_SOMNIA_RPC ?? 'https://dream-rpc.somnia.network',
    ),
  },
  ssr: true,
});
