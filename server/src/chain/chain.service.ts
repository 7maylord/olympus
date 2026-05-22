import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getContract,
  http,
  type PublicClient,
  type WalletClient,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

import AgentRegistryAbi   from './abis/AgentRegistry.json';
import ExecutionVerifierAbi from './abis/ExecutionVerifier.json';
import TaskRegistryAbi    from './abis/TaskRegistry.json';

@Injectable()
export class ChainService {
  readonly publicClient:  PublicClient;
  readonly walletClient:  WalletClient;
  readonly taskRegistry:  ReturnType<typeof getContract>;
  readonly agentRegistry: ReturnType<typeof getContract>;
  readonly executionVerifier: ReturnType<typeof getContract>;

  constructor(private config: ConfigService) {
    const rpcUrl  = config.get<string>('chain.rpcUrl')!;
    const chainId = config.get<number>('chain.chainId')!;

    const somniaTestnet = defineChain({
      id:   chainId,
      name: 'Somnia Testnet',
      nativeCurrency: { name: 'STT', symbol: 'STT', decimals: 18 },
      rpcUrls: { default: { http: [rpcUrl] } },
    });

    this.publicClient = createPublicClient({ chain: somniaTestnet, transport: http(rpcUrl) });

    const rawKey = config.get<string>('chain.keeperPrivateKey');
    const account = rawKey
      ? privateKeyToAccount(rawKey as `0x${string}`)
      : undefined;

    this.walletClient = createWalletClient({ chain: somniaTestnet, transport: http(rpcUrl), account });

    const taskRegistryAddress   = config.get<`0x${string}`>('chain.taskRegistryAddress')!;
    const agentRegistryAddress  = config.get<`0x${string}`>('chain.agentRegistryAddress')!;
    const executionVerifierAddress = config.get<`0x${string}`>('chain.executionVerifierAddress')!;

    this.taskRegistry = getContract({
      address: taskRegistryAddress,
      abi:     TaskRegistryAbi.abi,
      client:  { public: this.publicClient, wallet: this.walletClient },
    });

    this.agentRegistry = getContract({
      address: agentRegistryAddress,
      abi:     AgentRegistryAbi.abi,
      client:  { public: this.publicClient, wallet: this.walletClient },
    });

    this.executionVerifier = getContract({
      address: executionVerifierAddress,
      abi:     ExecutionVerifierAbi.abi,
      client:  { public: this.publicClient, wallet: this.walletClient },
    });
  }
}
