'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, encodeAbiParameters, keccak256, toBytes } from 'viem';
import { TASK_REGISTRY_ADDRESS, TaskRegistryABI, CLAIM_BOND, LISTING_FEE } from '../lib/contracts';

export type TaskStatus = 0 | 1 | 2 | 3 | 4; // Open, Claimed, Executed, Expired, Disputed

export interface OnChainTask {
  poster: `0x${string}`;
  capabilityTag: `0x${string}`;
  triggerCondition: `0x${string}`;
  targetAction: `0x${string}`;
  bounty: bigint;
  expiry: bigint;
  minAgentReputation: bigint;
  status: TaskStatus;
  claimedBy: `0x${string}`;
  claimedAt: bigint;
  claimWindowSeconds: bigint;
}

export function useGetTask(taskId: bigint | undefined) {
  return useReadContract({
    address: TASK_REGISTRY_ADDRESS,
    abi: TaskRegistryABI,
    functionName: 'getTask',
    args: taskId ? [taskId] : undefined,
    query: { enabled: !!taskId && TASK_REGISTRY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  });
}

export function useTaskCount() {
  return useReadContract({
    address: TASK_REGISTRY_ADDRESS,
    abi: TaskRegistryABI,
    functionName: 'taskCount',
    query: { enabled: TASK_REGISTRY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  });
}

export interface PostTaskParams {
  capabilityTag: string;         // e.g. 'SWAP'
  triggerType: 'none' | 'price' | 'health' | 'apy' | 'block';
  triggerParams: Record<string, string | number>;
  targetAction: Record<string, string | number>;
  bountyEth: string;             // e.g. '0.05'
  expiryTimestamp: number;       // unix seconds
  minAgentReputation: number;
  claimWindowSeconds: number;
}

function encodeCapabilityTag(tag: string): `0x${string}` {
  return keccak256(toBytes(tag));
}

// Map common token symbols to CoinGecko asset IDs (used by SomniaAgentsAdapter)
const COINGECKO_IDS: Record<string, string> = {
  ETH: 'ethereum', BTC: 'bitcoin', SOL: 'solana',
  USDC: 'usd-coin', USDT: 'tether', MATIC: 'matic-network',
};

function encodeTrigger(type: string, params: Record<string, string | number>): `0x${string}` {
  if (type === 'none') return '0x';

  // TriggerCondition enum: PriceBelow=0, PriceAbove=1, HealthFactor=2, APYSpread=3, BlockInterval=4
  let typeNum: number;
  let encodedParams: `0x${string}`;

  if (type === 'price') {
    // PriceBelow=0, PriceAbove=1
    typeNum = String(params.direction).toLowerCase() === 'above' ? 1 : 0;
    const symbol = String(params.tokenSymbol ?? '').toUpperCase();
    const tokenId = COINGECKO_IDS[symbol] ?? symbol.toLowerCase();
    const thresholdUSD18 = BigInt(Math.round(Number(params.threshold) * 1e18));
    encodedParams = encodeAbiParameters(
      [{ type: 'string' }, { type: 'uint256' }],
      [tokenId, thresholdUSD18],
    );
  } else if (type === 'health') {
    typeNum = 2;
    const minHF18 = BigInt(Math.round(Number(params.threshold) * 1e18));
    encodedParams = encodeAbiParameters(
      [{ type: 'string' }, { type: 'address' }, { type: 'uint256' }],
      [String(params.protocol), String(params.user) as `0x${string}`, minHF18],
    );
  } else if (type === 'apy') {
    typeNum = 3;
    // spreadPct → basis points (1% = 100 bps)
    const spreadBPS = BigInt(Math.round(Number(params.spreadPct) * 100));
    encodedParams = encodeAbiParameters(
      [{ type: 'string' }, { type: 'string' }, { type: 'uint256' }],
      [String(params.protocolA), String(params.protocolB), spreadBPS],
    );
  } else if (type === 'block') {
    typeNum = 4;
    // anchorBlock=0 placeholder; contract will interpret relative to current block
    const intervalBlocks = BigInt(Number(params.intervalBlocks));
    encodedParams = encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'uint256' }],
      [0n, intervalBlocks],
    );
  } else {
    return '0x';
  }

  // Outer encoding matches TriggerCondition struct: (uint8 triggerType, bytes params)
  return encodeAbiParameters(
    [{ type: 'uint8' }, { type: 'bytes' }],
    [typeNum, encodedParams],
  );
}

function encodeAction(params: Record<string, string | number>): `0x${string}` {
  return encodeAbiParameters([{ type: 'string' }], [JSON.stringify(params)]);
}

export function usePostTask() {
  const { writeContract, data: hash, isPending, isError, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } = useWaitForTransactionReceipt({ hash });

  const postTask = (params: PostTaskParams) => {
    const capabilityTag = encodeCapabilityTag(params.capabilityTag);
    const triggerCondition = encodeTrigger(params.triggerType, params.triggerParams);
    const targetAction = encodeAction(params.targetAction);
    const bountyWei = parseEther(params.bountyEth);
    const totalValue = bountyWei + LISTING_FEE;

    writeContract({
      address: TASK_REGISTRY_ADDRESS,
      abi: TaskRegistryABI,
      functionName: 'postTask',
      args: [
        capabilityTag,
        triggerCondition,
        targetAction,
        BigInt(params.minAgentReputation),
        BigInt(params.expiryTimestamp),
        BigInt(params.claimWindowSeconds),
      ],
      value: totalValue,
      gas: 400000n,
    });
  };

  const combinedError = error ?? receiptError ?? null;
  return { postTask, hash, isPending, isConfirming, isSuccess, isError: isError || isReceiptError, error: combinedError, reset };
}

export function useClaimTask(taskId: bigint | undefined) {
  const { writeContract, data: hash, isPending, isError, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const claimTask = () => {
    if (!taskId) return;
    writeContract({
      address: TASK_REGISTRY_ADDRESS,
      abi: TaskRegistryABI,
      functionName: 'claimTask',
      args: [taskId],
      value: CLAIM_BOND,
      gas: 300000n,
    });
  };

  return { claimTask, hash, isPending, isConfirming, isSuccess, isError, error };
}

export function useExpireTask(taskId: bigint | undefined) {
  const { writeContract, data: hash, isPending, isError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const expireTask = () => {
    if (!taskId) return;
    writeContract({
      address: TASK_REGISTRY_ADDRESS,
      abi: TaskRegistryABI,
      functionName: 'expireTask',
      args: [taskId],
      gas: 200000n,
    });
  };

  return { expireTask, hash, isPending, isConfirming, isSuccess, isError };
}

export function useSubmitProof(taskId: bigint | undefined) {
  const { writeContract, data: hash, isPending, isError, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const submitProof = (proofTxHash: `0x${string}`) => {
    if (!taskId) return;
    writeContract({
      address: TASK_REGISTRY_ADDRESS,
      abi: TaskRegistryABI,
      functionName: 'submitProof',
      args: [taskId, proofTxHash],
      gas: 200000n,
    });
  };

  return { submitProof, hash, isPending, isConfirming, isSuccess, isError, error };
}
