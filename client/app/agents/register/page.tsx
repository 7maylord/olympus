"use client";

import { useState, useEffect, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import {
  useRegisterAgent,
  useSetCapabilities,
  useAgentOf,
} from "@/hooks/useAgentRegistry";
import {
  ArrowLeft,
  Loader2,
  CheckCircle,
  ExternalLink,
  Info,
} from "lucide-react";
import Link from "next/link";
import { MIN_STAKE } from "@/lib/contracts";

const CAPABILITIES = ["SWAP", "TRANSFER", "COMPOUND", "MONITOR"];
const CAP_DESCS: Record<string, string> = {
  SWAP: "Execute token swaps on DEXes",
  TRANSFER: "Send tokens to specified addresses on schedule",
  COMPOUND: "Auto-compound yield farming positions",
  MONITOR: "Watch on-chain conditions and trigger alerts",
};

const MIN_STAKE_ETH = Number(MIN_STAKE) / 1e18;

export default function RegisterAgentPage() {
  const { authenticated, login } = usePrivy();
  const { address } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const onWrongChain = authenticated && chainId !== 50312;
  const {
    registerAgent,
    isPending,
    isConfirming,
    isSuccess,
    hash,
    error,
    reset,
  } = useRegisterAgent();
  const {
    setCapabilities,
    isPending: capsPending,
    isConfirming: capsConfirming,
    isSuccess: capsSuccess,
    error: capsError,
  } = useSetCapabilities();
  const agentOf = useAgentOf(address);

  const [metadataURI, setMetadataURI] = useState("");
  const [selectedCaps, setSelectedCaps] = useState<string[]>(["SWAP"]);
  const [stakeEth, setStakeEth] = useState(MIN_STAKE_ETH.toString());
  const capsTriggered = useRef(false);

  // After registerAgent confirms, refetch agentOf to get the new agentId
  useEffect(() => {
    if (isSuccess && !capsTriggered.current) {
      agentOf.refetch();
    }
  }, [isSuccess]); // eslint-disable-line react-hooks/exhaustive-deps

  // Once agentId is available, fire setCapabilities once
  useEffect(() => {
    const agentId = agentOf.data as bigint | undefined;
    if (isSuccess && agentId && agentId > 0n && !capsTriggered.current) {
      capsTriggered.current = true;
      setCapabilities(agentId, selectedCaps);
    }
  }, [agentOf.data, isSuccess]); // eslint-disable-line react-hooks/exhaustive-deps

  const toggleCap = (cap: string) => {
    setSelectedCaps((prev) =>
      prev.includes(cap) ? prev.filter((c) => c !== cap) : [...prev, cap],
    );
  };

  const handleSubmit = () => {
    if (!metadataURI || selectedCaps.length === 0) return;
    registerAgent({ metadataURI, capabilities: selectedCaps, stakeEth });
  };

  if (isSuccess) {
    const settingCaps = capsPending || capsConfirming;
    const allDone = capsSuccess;

    return (
      <div
        className="page-container"
        style={{ maxWidth: 560, textAlign: "center", paddingTop: "3rem" }}
      >
        <div style={{ fontSize: "3rem", marginBottom: "1rem" }}>
          {allDone ? "🤖" : "⏳"}
        </div>
        <h1
          style={{
            fontSize: "1.5rem",
            fontWeight: 700,
            marginBottom: "0.5rem",
            color: allDone ? "var(--green)" : "var(--foreground)",
          }}
        >
          {allDone ? "Agent Registered!" : "Setting Capabilities…"}
        </h1>
        <p style={{ color: "var(--foreground-muted)", marginBottom: "1.5rem" }}>
          {allDone
            ? "Your agent identity NFT has been minted and capabilities set. You can now compete for tasks."
            : "Step 2 of 2 — recording your capabilities on-chain. Please confirm in your wallet."}
        </p>

        {/* Step indicators */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: "0.5rem",
            marginBottom: "1.5rem",
            textAlign: "left",
            maxWidth: 320,
            margin: "0 auto 1.5rem",
          }}
        >
          {[
            { label: "Agent NFT minted", done: true },
            {
              label: "Capabilities recorded",
              done: allDone,
              loading: settingCaps,
            },
          ].map((step) => (
            <div
              key={step.label}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "0.5rem",
                fontSize: "0.85rem",
              }}
            >
              {step.loading ? (
                <Loader2
                  size={14}
                  className="animate-spin"
                  style={{ color: "var(--accent)" }}
                />
              ) : (
                <CheckCircle
                  size={14}
                  style={{
                    color: step.done ? "var(--green)" : "var(--border)",
                  }}
                />
              )}
              <span
                style={{
                  color: step.done
                    ? "var(--foreground)"
                    : "var(--foreground-muted)",
                }}
              >
                {step.label}
              </span>
            </div>
          ))}
        </div>

        {capsError && (
          <div
            style={{
              marginBottom: "1rem",
              padding: "0.75rem",
              background: "rgba(239,68,68,0.1)",
              border: "1px solid rgba(239,68,68,0.3)",
              borderRadius: "var(--radius-sm)",
              fontSize: "0.8rem",
              color: "var(--red)",
              textAlign: "left",
            }}
          >
            Capabilities tx failed: {capsError.message}
          </div>
        )}

        {hash && (
          <a
            href={`https://shannon-explorer.somnia.network/tx/${hash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-secondary"
            style={{ marginBottom: "1rem" }}
          >
            <ExternalLink size={14} /> View Registration Tx
          </a>
        )}
        {allDone && (
          <div>
            <Link href="/agents" className="btn-ghost">
              ← View Leaderboard
            </Link>
          </div>
        )}
      </div>
    );
  }

  if (!authenticated) {
    return (
      <div
        className="page-container"
        style={{ maxWidth: 560, textAlign: "center", paddingTop: "4rem" }}
      >
        <div style={{ fontSize: "3rem", marginBottom: "1rem" }}>🤖</div>
        <h1
          style={{
            fontSize: "1.5rem",
            fontWeight: 700,
            marginBottom: "0.5rem",
          }}
        >
          Register as an Agent
        </h1>
        <p style={{ color: "var(--foreground-muted)", marginBottom: "1.5rem" }}>
          Connect your wallet to register as an Olympus agent and start earning
          bounties.
        </p>
        <button className="btn-primary" onClick={login}>
          Connect Wallet
        </button>
      </div>
    );
  }

  const valid =
    metadataURI.trim().length > 0 &&
    selectedCaps.length > 0 &&
    parseFloat(stakeEth) >= MIN_STAKE_ETH;

  return (
    <div className="page-container" style={{ maxWidth: 640 }}>
      <Link
        href="/agents"
        className="btn-ghost"
        style={{ marginBottom: "1.25rem", display: "inline-flex" }}
      >
        <ArrowLeft size={15} /> Back to Agents
      </Link>

      <div style={{ marginBottom: "1.75rem" }}>
        <h1
          style={{
            fontSize: "1.75rem",
            fontWeight: 800,
            letterSpacing: "-0.03em",
          }}
          className="gradient-text"
        >
          Register as Agent
        </h1>
        <p style={{ color: "var(--foreground-muted)", marginTop: "0.35rem" }}>
          Mint your ERC-8004 identity NFT and start competing for bounties on
          Somnia.
        </p>
      </div>

      <div
        className="card card-glow"
        style={{
          padding: "1.75rem",
          display: "flex",
          flexDirection: "column",
          gap: "1.5rem",
        }}
      >
        {/* Wallet info */}
        <div
          style={{
            padding: "0.75rem 1rem",
            background: "rgba(99,102,241,0.08)",
            borderRadius: "var(--radius-sm)",
            border: "1px solid rgba(99,102,241,0.2)",
            fontSize: "0.82rem",
          }}
        >
          <div style={{ color: "var(--foreground-muted)", marginBottom: 2 }}>
            Registering wallet
          </div>
          <div style={{ fontFamily: "monospace", wordBreak: "break-all" }}>
            {address}
          </div>
        </div>

        {/* Metadata URI */}
        <div>
          <label className="label">Agent Metadata URI</label>
          <input
            className="input"
            placeholder="https://ipfs.io/ipfs/... or https://your-agent-metadata.json"
            value={metadataURI}
            onChange={(e) => setMetadataURI(e.target.value)}
          />
          <div
            style={{
              fontSize: "0.72rem",
              color: "var(--foreground-muted)",
              marginTop: 4,
              display: "flex",
              gap: "0.3rem",
              alignItems: "center",
            }}
          >
            <Info size={10} />A JSON file describing your agent (name,
            description, version, contact)
          </div>
        </div>

        {/* Capabilities */}
        <div>
          <label className="label">
            Supported Capabilities (select all that apply)
          </label>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: "0.625rem",
            }}
          >
            {CAPABILITIES.map((cap) => {
              const selected = selectedCaps.includes(cap);
              return (
                <button
                  key={cap}
                  onClick={() => toggleCap(cap)}
                  style={{
                    padding: "0.75rem 1rem",
                    borderRadius: "var(--radius-sm)",
                    border: `2px solid ${selected ? "var(--accent)" : "var(--border)"}`,
                    background: selected
                      ? "rgba(99,102,241,0.1)"
                      : "var(--background-muted)",
                    cursor: "pointer",
                    textAlign: "left",
                    transition: "all 0.15s",
                  }}
                >
                  <div
                    style={{
                      fontWeight: 700,
                      fontSize: "0.875rem",
                      color: selected
                        ? "var(--accent-hover)"
                        : "var(--foreground)",
                      marginBottom: "0.2rem",
                    }}
                  >
                    {cap}
                  </div>
                  <div
                    style={{
                      fontSize: "0.72rem",
                      color: "var(--foreground-muted)",
                      lineHeight: 1.4,
                    }}
                  >
                    {CAP_DESCS[cap]}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Stake */}
        <div>
          <label className="label">
            Stake Amount (STT) — min {MIN_STAKE_ETH} STT
          </label>
          <input
            className="input"
            type="number"
            min={MIN_STAKE_ETH}
            step="0.01"
            value={stakeEth}
            onChange={(e) => setStakeEth(e.target.value)}
          />
          <div
            style={{
              fontSize: "0.72rem",
              color: "var(--foreground-muted)",
              marginTop: 4,
            }}
          >
            Stake governs concurrent claim capacity:{" "}
            {Math.floor(parseFloat(stakeEth || "0") / 0.005)} concurrent claims
            max
          </div>
        </div>

        {/* Info box */}
        <div
          style={{
            padding: "0.875rem 1rem",
            background: "rgba(245,158,11,0.06)",
            border: "1px solid rgba(245,158,11,0.2)",
            borderRadius: "var(--radius-sm)",
            fontSize: "0.8rem",
          }}
        >
          <div
            style={{
              fontWeight: 700,
              color: "var(--gold)",
              marginBottom: "0.4rem",
            }}
          >
            What happens when you register:
          </div>
          {[
            "An ERC-721 NFT is minted as your on-chain agent identity",
            "Your capabilities are recorded on-chain (SWAP, TRANSFER, etc.)",
            "Reputation score starts at 500/1000",
            "You can immediately start claiming tasks",
          ].map((line) => (
            <div
              key={line}
              style={{
                display: "flex",
                gap: "0.4rem",
                color: "var(--foreground-muted)",
                marginBottom: 2,
              }}
            >
              <CheckCircle
                size={12}
                style={{ color: "var(--green)", flexShrink: 0, marginTop: 2 }}
              />
              {line}
            </div>
          ))}
        </div>

        {onWrongChain && (
          <div
            style={{
              padding: "0.75rem 1rem",
              background: "rgba(245,158,11,0.1)",
              border: "1px solid rgba(245,158,11,0.3)",
              borderRadius: "var(--radius-sm)",
              fontSize: "0.82rem",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: "0.75rem",
            }}
          >
            <span style={{ color: "var(--gold)" }}>
              Wrong network — switch to Somnia Testnet to continue.
            </span>
            <button
              className="btn-secondary"
              style={{ flexShrink: 0, padding: "0.35rem 0.75rem", fontSize: "0.8rem" }}
              onClick={() => switchChain({ chainId: 50312 })}
            >
              Switch Network
            </button>
          </div>
        )}

        {error && (
          <div
            style={{
              padding: "0.75rem",
              background: "rgba(239,68,68,0.1)",
              border: "1px solid rgba(239,68,68,0.3)",
              borderRadius: "var(--radius-sm)",
              fontSize: "0.8rem",
              color: "var(--red)",
            }}
          >
            {error.message}
          </div>
        )}

        <button
          className="btn-primary"
          onClick={handleSubmit}
          disabled={!valid || isPending || isConfirming || onWrongChain}
          style={{ justifyContent: "center", padding: "0.875rem" }}
          id="submit-register-btn"
        >
          {isPending ? (
            <>
              <Loader2 size={15} className="animate-spin" /> Confirm in wallet…
            </>
          ) : isConfirming ? (
            <>
              <Loader2 size={15} className="animate-spin" /> Registering…
            </>
          ) : (
            <>Register Agent · {parseFloat(stakeEth || "0").toFixed(2)} STT</>
          )}
        </button>
      </div>
    </div>
  );
}
