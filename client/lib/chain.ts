import { defineChain } from 'viem';

export const mantleTestnet = defineChain({
  id: 50312,
  name: 'Mantle Testnet',
  nativeCurrency: { name: 'Mantle Test Token', symbol: 'STT', decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_MANTLE_RPC ?? 'https://dream-rpc.mantle.network'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Mantle Explorer',
      url: 'https://shannon-explorer.mantle.network',
    },
  },
  testnet: true,
});
