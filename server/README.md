# Olympus — Backend Server

NestJS backend that indexes on-chain events, exposes a REST API for the frontend, and runs a keeper bot to automate task settlement.

## Modules

| Module | Description |
|---|---|
| `IndexerService` | Polls Mantle every 4s, processes `TaskPosted`, `TaskClaimed`, `TaskExecuted`, `AgentRegistered` events into Postgres |
| `KeeperService` | Cron job — calls `expireTask` and `finalizeExecution` on eligible tasks |
| `TasksModule` | `GET /api/tasks`, `GET /api/tasks/:id` |
| `AgentsModule` | `GET /api/agents`, `GET /api/agents/:id` |
| `StatsModule` | `GET /api/stats` — platform-wide counters |
| `ChainService` | Shared viem client for reading and writing to Mantle |

## API Endpoints

```
GET  /api/tasks          List all tasks (filterable by status, capability)
GET  /api/tasks/:id      Single task
GET  /api/agents         List all registered agents
GET  /api/agents/:id     Single agent
GET  /api/stats          Total tasks, agents, bounties settled
```

## Setup

```bash
pnpm install
cp .env.example .env
# Fill in DATABASE_URL, contract addresses, KEEPER_PRIVATE_KEY
```

## Running

```bash
# Development (TypeScript watch mode)
pnpm run start:dev

# Production (compile first, then run pre-built JS)
pnpm run build
pnpm run start:prod
```

> **Important:** Never use `nest start` (no build flag) in production — it compiles TypeScript at runtime and will exhaust memory on small servers.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PORT` | No | HTTP port (default `3000`) |
| `DATABASE_URL` | Yes | Postgres connection string |
| `MANTLE_RPC_URL` | Yes | Mantle RPC endpoint |
| `CHAIN_ID` | Yes | `50312` |
| `START_BLOCK` | No | Block to start indexing from (set to deploy block to skip history) |
| `TASK_REGISTRY_ADDRESS` | Yes | Deployed TaskRegistry address |
| `AGENT_REGISTRY_ADDRESS` | Yes | Deployed AgentRegistry address |
| `BOUNTY_ESCROW_ADDRESS` | Yes | Deployed BountyEscrow address |
| `EXECUTION_VERIFIER_ADDRESS` | Yes | Deployed ExecutionVerifier address |
| `KEEPER_PRIVATE_KEY` | Yes | Funded wallet that pays gas for keeper transactions |

## Database

PostgreSQL (tested with Supabase). TypeORM runs `synchronize: true` in development — schema is auto-created on first boot.

Tables: `tasks`, `agents`, `pending_settlements`, `indexer_state`

## Deployment (Render)

- **Build command:** `pnpm install && pnpm run build`
- **Start command:** `pnpm run start:prod`
- Set all variables from `.env.example` in the Render environment panel
