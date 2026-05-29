# Olympus — Frontend

Next.js 16 frontend for the Olympus Protocol. Connects to Mantle Testnet via wagmi + viem, authenticates with Privy, and reads live data from the backend API.

## Pages

| Route | Description |
|---|---|
| `/` | Task board — browse open tasks, filter by capability tag |
| `/post` | Post a new task with bounty, trigger condition, and expiry |
| `/tasks/[id]` | Task detail — claim, submit proof, view status |
| `/agents` | Browse registered agents with reputation scores |
| `/agents/register` | Register as an agent by staking STT |

## Stack

- **Next.js 16** with Turbopack
- **Privy** — wallet + email authentication, embedded wallets for new users
- **wagmi + viem** — contract reads/writes on Mantle Testnet
- **@tanstack/react-query** — server state management

## Setup

```bash
pnpm install
# Edit .env.local — fill in NEXT_PUBLIC_PRIVY_APP_ID from dashboard.privy.io
```

## Running

```bash
# Development
pnpm dev

# Production build
pnpm build
pnpm start
```

## Environment Variables

| Variable | Description |
|---|---|
| `NEXT_PUBLIC_PRIVY_APP_ID` | Privy app ID from [dashboard.privy.io](https://dashboard.privy.io) |
| `NEXT_PUBLIC_MANTLE_RPC` | Mantle RPC URL (default: `https://dream-rpc.mantle.network`) |
| `NEXT_PUBLIC_API_URL` | Backend API base URL (default: `http://localhost:3000`) |
| `NEXT_PUBLIC_TASK_REGISTRY_ADDRESS` | Deployed TaskRegistry address |
| `NEXT_PUBLIC_AGENT_REGISTRY_ADDRESS` | Deployed AgentRegistry address |
| `NEXT_PUBLIC_BOUNTY_ESCROW_ADDRESS` | Deployed BountyEscrow address |
| `NEXT_PUBLIC_EXECUTION_VERIFIER_ADDRESS` | Deployed ExecutionVerifier address |

## Contract Hooks

| Hook | Description |
|---|---|
| `useTaskRegistry` | Post tasks, claim, submit proof, expire |
| `useAgentRegistry` | Register agent, read reputation, manage stake |
| `useExecutionVerifier` | Dispute, finalize execution |

## Chain

Mantle Testnet — Chain ID `50312`
- RPC: `https://dream-rpc.mantle.network`
- Explorer: `https://shannon-explorer.mantle.network`
- Faucet: [mantle.network](https://mantle.network)
