const BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  });
  if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);
  return res.json() as Promise<T>;
}

export type TaskStatus = 'Open' | 'Claimed' | 'Executed' | 'Expired' | 'Disputed';

export interface ApiTask {
  id: string;
  poster: string;
  capabilityTag: string;
  bounty: string;
  status: TaskStatus;
  claimedBy?: string;
  claimedAt?: number;
  executedAt?: number;
  proofHash?: string;
  latencyMs?: number;
  expiry: string;
}

export interface ApiAgent {
  id: string;
  operator: string;
  reputationScore: number;
  tasksCompleted: number;
  tasksFailed: number;
  totalEarned: string;
}

export interface ApiStats {
  totalTasks: number;
  openTasks: number;
  totalAgents: number;
  totalBounties: string;
  completionRate: number;
  avgClaimTimeMs: number;
}

export const api = {
  getTasks: (params?: {
    status?: TaskStatus;
    capabilityTag?: string;
    poster?: string;
    minBounty?: string;
    page?: number;
    limit?: number;
  }) => {
    const qs = new URLSearchParams();
    if (params?.status) qs.set('status', params.status);
    if (params?.capabilityTag) qs.set('capabilityTag', params.capabilityTag);
    if (params?.poster) qs.set('poster', params.poster);
    if (params?.minBounty) qs.set('minBounty', params.minBounty);
    if (params?.page) qs.set('page', String(params.page));
    if (params?.limit) qs.set('limit', String(params.limit));
    return request<ApiTask[]>(`/api/tasks?${qs}`);
  },

  getTask: (id: string) => request<ApiTask>(`/api/tasks/${id}`),

  getAgents: (limit = 50) => request<ApiAgent[]>(`/api/agents?limit=${limit}`),

  getAgent: (identifier: string) => request<ApiAgent>(`/api/agents/${identifier}`),

  getStats: () => request<ApiStats>('/api/stats'),
};
