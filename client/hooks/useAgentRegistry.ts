'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from 'wagmi';
import { parseEther, keccak256, toBytes } from 'viem';
import { AGENT_REGISTRY_ADDRESS, AgentRegistryABI, MIN_STAKE } from '../lib/contracts';

export function useAgentOf(address: `0x${string}` | undefined) {
  return useReadContract({
    address: AGENT_REGISTRY_ADDRESS,
    abi: AgentRegistryABI,
    functionName: 'agentOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address && AGENT_REGISTRY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  });
}

export function useAgentData(agentId: bigint | undefined) {
  return useReadContract({
    address: AGENT_REGISTRY_ADDRESS,
    abi: AgentRegistryABI,
    functionName: 'agentData',
    args: agentId ? [agentId] : undefined,
    query: { enabled: !!agentId && AGENT_REGISTRY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  });
}

export function useFeedback(agentId: bigint | undefined) {
  return useReadContract({
    address: AGENT_REGISTRY_ADDRESS,
    abi: AgentRegistryABI,
    functionName: 'getFeedback',
    args: agentId ? [agentId] : undefined,
    query: { enabled: !!agentId && AGENT_REGISTRY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  });
}

export function useMyAgent() {
  const { address } = useAccount();
  const agentOfResult = useAgentOf(address);
  const agentId = agentOfResult.data as bigint | undefined;
  const agentDataResult = useAgentData(agentId && agentId > 0n ? agentId : undefined);
  return {
    agentId: agentId && agentId > 0n ? agentId : undefined,
    agentData: agentDataResult.data,
    isRegistered: !!agentId && agentId > 0n,
    isLoading: agentOfResult.isLoading || agentDataResult.isLoading,
  };
}

export interface RegisterAgentParams {
  metadataURI: string;
  capabilities: string[];   // e.g. ['SWAP', 'COMPOUND']
  stakeEth?: string;        // default 0.01
}

export function useRegisterAgent() {
  const { writeContract, data: hash, isPending, isError, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const registerAgent = (params: RegisterAgentParams) => {
    const stake = parseEther(params.stakeEth ?? '0.01');
    const capabilityTags = params.capabilities.map((cap) => keccak256(toBytes(cap))) as `0x${string}`[];

    writeContract({
      address: AGENT_REGISTRY_ADDRESS,
      abi: AgentRegistryABI,
      functionName: 'registerAgent',
      args: [params.metadataURI],
      value: stake,
    });
  };

  return { registerAgent, hash, isPending, isConfirming, isSuccess, isError, error, reset };
}

export function useSetCapabilities() {
  const { writeContract, data: hash, isPending, isError, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const setCapabilities = (agentId: bigint, capabilities: string[]) => {
    const capabilityTags = capabilities.map((cap) => keccak256(toBytes(cap))) as `0x${string}`[];
    writeContract({
      address: AGENT_REGISTRY_ADDRESS,
      abi: AgentRegistryABI,
      functionName: 'setCapabilities',
      args: [agentId, capabilityTags],
    });
  };

  return { setCapabilities, hash, isPending, isConfirming, isSuccess, isError, error };
}
