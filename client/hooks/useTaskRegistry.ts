'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from 'wagmi';
import { parseEther, encodeAbiParameters, keccak256, toBytes } from 'viem';
import { TASK_REGISTRY_ADDRESS, TaskRegistryABI, CLAIM_BOND, MIN_BOUNTY, LISTING_FEE } from '../lib/contracts';

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

function encodeTrigger(type: string, params: Record<string, string | number>): `0x${string}` {
  if (type === 'none') return '0x';
  const typeMap: Record<string, number> = { price: 0, health: 1, apy: 2, block: 3 };
  const typeNum = typeMap[type] ?? 0;
  return encodeAbiParameters(
    [{ type: 'uint8' }, { type: 'bytes' }],
    [typeNum, encodeAbiParameters(
      [{ type: 'string' }],
      [JSON.stringify(params)],
    )],
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
