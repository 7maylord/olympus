export default () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  database: {
    url:      process.env.DATABASE_URL ?? '',
    host:     process.env.DB_HOST      ?? 'localhost',
    port:     parseInt(process.env.DB_PORT ?? '5432', 10),
    username: process.env.DB_USER      ?? 'postgres',
    password: process.env.DB_PASSWORD  ?? 'postgres',
    name:     process.env.DB_NAME      ?? 'olympus',
  },
  chain: {
    rpcUrl:              process.env.SOMNIA_RPC_URL            ?? 'https://dream-rpc.somnia.network',
    chainId:             parseInt(process.env.CHAIN_ID         ?? '50312', 10),
    taskRegistryAddress: process.env.TASK_REGISTRY_ADDRESS     ?? '',
    agentRegistryAddress:process.env.AGENT_REGISTRY_ADDRESS    ?? '',
    bountyEscrowAddress: process.env.BOUNTY_ESCROW_ADDRESS     ?? '',
    executionVerifierAddress: process.env.EXECUTION_VERIFIER_ADDRESS ?? '',
    keeperPrivateKey:    process.env.KEEPER_PRIVATE_KEY        ?? '',
    startBlock:          BigInt(process.env.START_BLOCK        ?? '0'),
  },
});
