'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { EXECUTION_VERIFIER_ADDRESS, ExecutionVerifierABI } from '../lib/contracts';

export function useIsDisputable(taskId: bigint | undefined) {
  return useReadContract({
    address: EXECUTION_VERIFIER_ADDRESS,
    abi: ExecutionVerifierABI,
    functionName: 'isDisputable',
    args: taskId ? [taskId] : undefined,
    query: {
      enabled: !!taskId && EXECUTION_VERIFIER_ADDRESS !== '0x0000000000000000000000000000000000000000',
      refetchInterval: 10_000,
    },
  });
}

export function useIsFinalizable(taskId: bigint | undefined) {
  return useReadContract({
    address: EXECUTION_VERIFIER_ADDRESS,
    abi: ExecutionVerifierABI,
    functionName: 'isFinalizable',
    args: taskId ? [taskId] : undefined,
    query: {
      enabled: !!taskId && EXECUTION_VERIFIER_ADDRESS !== '0x0000000000000000000000000000000000000000',
      refetchInterval: 10_000,
    },
  });
}

export function usePendingSettlement(taskId: bigint | undefined) {
  return useReadContract({
    address: EXECUTION_VERIFIER_ADDRESS,
    abi: ExecutionVerifierABI,
    functionName: 'pending',
    args: taskId ? [taskId] : undefined,
    query: {
      enabled: !!taskId && EXECUTION_VERIFIER_ADDRESS !== '0x0000000000000000000000000000000000000000',
      refetchInterval: 15_000,
    },
  });
}

export function useFinalizeExecution(taskId: bigint | undefined) {
  const { writeContract, data: hash, isPending, isError, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const finalizeExecution = () => {
    if (!taskId) return;
    writeContract({
      address: EXECUTION_VERIFIER_ADDRESS,
      abi: ExecutionVerifierABI,
      functionName: 'finalizeExecution',
      args: [taskId],
    });
  };

  return { finalizeExecution, hash, isPending, isConfirming, isSuccess, isError, error };
}

export function useDisputeExecution(taskId: bigint | undefined) {
  const { writeContract, data: hash, isPending, isError, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const disputeExecution = () => {
    if (!taskId) return;
    writeContract({
      address: EXECUTION_VERIFIER_ADDRESS,
      abi: ExecutionVerifierABI,
      functionName: 'disputeExecution',
      args: [taskId],
    });
  };

  return { disputeExecution, hash, isPending, isConfirming, isSuccess, isError, error };
}
