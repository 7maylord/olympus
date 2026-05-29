import { http, createConfig } from 'wagmi';
import { mantleTestnet } from './chain';

export const wagmiConfig = createConfig({
  chains: [mantleTestnet],
  transports: {
    [mantleTestnet.id]: http(
      process.env.NEXT_PUBLIC_MANTLE_RPC ?? 'https://dream-rpc.mantle.network',
    ),
  },
  ssr: true,
});
