"use client";

import { useParams } from "next/navigation";
import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { usePrivy } from "@privy-io/react-auth";
import {
  CheckCircle,
  AlertTriangle,
  ExternalLink,
  Copy,
  ArrowLeft,
  Loader2,
} from "lucide-react";
import Link from "next/link";
import { api } from "@/lib/api";
import type { ApiTask } from "@/lib/api";
import {
  useIsDisputable,
  useIsFinalizable,
  useFinalizeExecution,
  useDisputeExecution,
} from "@/hooks/useExecutionVerifier";
import {
  useClaimTask,
  useSubmitProof,
  useExpireTask,
} from "@/hooks/useTaskRegistry";
import { useMyAgent } from "@/hooks/useAgentRegistry";
import clsx from "clsx";

function copyToClipboard(text: string) {
  navigator.clipboard.writeText(text).catch(() => {});
}

function formatTs(ts: number): string {
  return new Date(ts * 1000).toLocaleString();
}

function formatBounty(wei: string): string {
  return (Number(BigInt(wei)) / 1e18).toFixed(6);
}

function StatusTimeline({ task }: { task: ApiTask }) {
  const steps: Array<{
    key: string;
    label: string;
    ts?: number;
    active: boolean;
  }> = [
    { key: "posted", label: "Task Posted", active: true },
    {
      key: "claimed",
      label: "Claimed",
      ts: task.claimedAt,
      active: !!task.claimedBy,
    },
    {
      key: "executed",
      label: "Executed",
      ts: task.executedAt,
      active: task.status === "Executed",
    },
    {
      key: "finalized",
      label: "Finalized",
      active: task.status === "Executed",
    },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
      {steps.map((step, i) => (
        <div
          key={step.key}
          style={{ display: "flex", alignItems: "flex-start", gap: "0.75rem" }}
        >
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 0,
            }}
          >
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: "50%",
                flexShrink: 0,
                background: step.active
                  ? "var(--green)"
                  : "var(--background-muted)",
                border: `2px solid ${step.active ? "var(--green)" : "var(--border)"}`,
                boxShadow: step.active ? "0 0 8px var(--green)" : "none",
              }}
            />
            {i < steps.length - 1 && (
              <div
                style={{
                  width: 2,
                  height: 28,
                  background: step.active
                    ? "rgba(16,185,129,0.3)"
                    : "var(--border)",
                  marginTop: 2,
                }}
              />
            )}
          </div>
          <div style={{ paddingTop: 1 }}>
            <div
              style={{
                fontSize: "0.825rem",
                fontWeight: step.active ? 600 : 400,
                color: step.active
                  ? "var(--foreground)"
                  : "var(--foreground-muted)",
              }}
            >
              {step.label}
            </div>
            {step.ts && (
              <div
                style={{
                  fontSize: "0.72rem",
                  color: "var(--foreground-muted)",
                }}
              >
                {formatTs(step.ts)}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

export default function TaskDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { address } = useAccount();
  const { authenticated } = usePrivy();

  const [task, setTask] = useState<ApiTask | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [copied, setCopied] = useState(false);
  const [proofInput, setProofInput] = useState("");

  const taskId = task ? BigInt(task.id) : undefined;
  const { isRegistered } = useMyAgent();

  const { data: isDisputable } = useIsDisputable(taskId);
  const { data: isFinalizable } = useIsFinalizable(taskId);

  const {
    claimTask,
    isPending: claimPending,
    isConfirming: claimConfirming,
    isSuccess: claimSuccess,
    error: claimError,
  } = useClaimTask(taskId);
  const {
    submitProof,
    isPending: proofPending,
    isConfirming: proofConfirming,
    isSuccess: proofSuccess,
    error: proofError,
  } = useSubmitProof(taskId);
  const {
    expireTask,
    isPending: expirePending,
    isConfirming: expireConfirming,
    isSuccess: expireSuccess,
  } = useExpireTask(taskId);
  const {
    finalizeExecution,
    isPending: finPending,
    isConfirming: finConfirming,
    isSuccess: finSuccess,
  } = useFinalizeExecution(taskId);
  const {
    disputeExecution,
    isPending: dispPending,
    isConfirming: dispConfirming,
    isSuccess: dispSuccess,
  } = useDisputeExecution(taskId);

  useEffect(() => {
    let cancelled = false;
    setLoadError(false);
    api
      .getTask(id)
      .then((data) => {
        if (!cancelled) setTask(data);
      })
      .catch(() => {
        if (!cancelled) setLoadError(true);
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  // Refresh task data after any successful action
  useEffect(() => {
    if (
      claimSuccess ||
      proofSuccess ||
      expireSuccess ||
      finSuccess ||
      dispSuccess
    ) {
      api
        .getTask(id)
        .then(setTask)
        .catch(() => {});
    }
  }, [claimSuccess, proofSuccess, expireSuccess, finSuccess, dispSuccess, id]);

  if (loadError) {
    return (
      <div
        className="page-container"
        style={{ textAlign: "center", paddingTop: "4rem" }}
      >
        <div style={{ fontSize: "2rem", marginBottom: "0.75rem" }}>🔍</div>
        <div style={{ fontWeight: 600, marginBottom: "0.5rem" }}>
          Task not found
        </div>
        <Link href="/" className="btn-ghost">
          ← Back to tasks
        </Link>
      </div>
    );
  }

  if (!task) {
    return (
      <div
        className="page-container"
        style={{ textAlign: "center", paddingTop: "4rem" }}
      >
        <div style={{ fontSize: "2rem", marginBottom: "0.75rem" }}>⏳</div>
        <div style={{ fontWeight: 600, marginBottom: "0.5rem" }}>
          Loading task…
        </div>
      </div>
    );
  }

  const isDisputableBool = Boolean(isDisputable);
  const isFinalizableBool = Boolean(isFinalizable);
  const isPoster = address?.toLowerCase() === task.poster.toLowerCase();
  const isClaimer = address?.toLowerCase() === task.claimedBy?.toLowerCase();
  const now = Math.floor(Date.now() / 1000);
  const isExpired = Number(task.expiry) < now;
  const canClaim =
    task.status === "Open" && !isExpired && isRegistered && !isPoster;
  const canSubmitProof = task.status === "Claimed" && isClaimer;
  const canExpire = task.status === "Open" && isExpired;
  const statusClass = `badge-${task.status.toLowerCase()}`;

  const handleCopy = (text: string) => {
    copyToClipboard(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="page-container" style={{ maxWidth: 860 }}>
      {/* Back */}
      <Link
        href="/"
        className="btn-ghost"
        style={{ marginBottom: "1.25rem", display: "inline-flex" }}
      >
        <ArrowLeft size={15} /> Back to tasks
      </Link>

      {/* Header */}
      <div className="card" style={{ padding: "1.5rem", marginBottom: "1rem" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            gap: "1rem",
            flexWrap: "wrap",
            marginBottom: "1rem",
          }}
        >
          <div>
            <div
              style={{
                fontSize: "0.75rem",
                color: "var(--foreground-muted)",
                marginBottom: "0.25rem",
                fontFamily: "monospace",
              }}
            >
              Task #{task.id}
            </div>
            <h1
              style={{
                fontSize: "1.5rem",
                fontWeight: 700,
                letterSpacing: "-0.03em",
              }}
            >
              {task.capabilityTag} Task
            </h1>
          </div>
          <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
            <span className={clsx("badge", statusClass)}>{task.status}</span>
            <div
              style={{
                fontWeight: 700,
                fontSize: "1.5rem",
                color: "var(--gold)",
                textShadow: "0 0 12px var(--gold-glow)",
              }}
            >
              {formatBounty(task.bounty)} STT
            </div>
          </div>
        </div>

        {/* Details grid */}
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
            gap: "0.75rem",
          }}
        >
          {[
            { label: "Poster", value: task.poster, mono: true },
            { label: "Capability", value: task.capabilityTag },
            {
              label: "Expiry",
              value: new Date(Number(task.expiry) * 1000).toLocaleString(),
            },
            task.claimedBy
              ? { label: "Claimed By", value: task.claimedBy, mono: true }
              : null,
            task.proofHash
              ? {
                  label: "Proof Hash",
                  value: `${task.proofHash.slice(0, 16)}…`,
                  mono: true,
                }
              : null,
            task.latencyMs
              ? {
                  label: "Execution Latency",
                  value: `${(task.latencyMs / 1000).toFixed(2)}s`,
                }
              : null,
          ]
            .filter(Boolean)
            .map(
              (item) =>
                item && (
                  <div
                    key={item.label}
                    style={{
                      padding: "0.75rem",
                      background: "var(--background-muted)",
                      borderRadius: "var(--radius-sm)",
                    }}
                  >
                    <div
                      style={{
                        fontSize: "0.7rem",
                        color: "var(--foreground-muted)",
                        textTransform: "uppercase",
                        letterSpacing: "0.06em",
                        marginBottom: "0.25rem",
                      }}
                    >
                      {item.label}
                    </div>
                    <div
                      style={{
                        fontSize: "0.8rem",
                        fontFamily: item.mono ? "monospace" : undefined,
                        wordBreak: "break-all",
                        cursor: item.mono ? "pointer" : undefined,
                      }}
                      onClick={
                        item.mono ? () => handleCopy(item.value) : undefined
                      }
                      title={item.mono ? "Click to copy" : undefined}
                    >
                      {item.value}
                      {item.mono && (
                        <Copy
                          size={11}
                          style={{ marginLeft: 4, opacity: 0.5 }}
                        />
                      )}
                    </div>
                  </div>
                ),
            )}
        </div>
      </div>

      <div
        style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem" }}
      >
        {/* Timeline */}
        <div className="card card-glow" style={{ padding: "1.25rem" }}>
          <h2
            style={{
              fontSize: "0.9rem",
              fontWeight: 700,
              marginBottom: "1rem",
              color: "var(--foreground-muted)",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}
          >
            Execution Timeline
          </h2>
          <StatusTimeline task={task} />
        </div>

        {/* Actions */}
        <div className="card card-glow" style={{ padding: "1.25rem" }}>
          <h2
            style={{
              fontSize: "0.9rem",
              fontWeight: 700,
              marginBottom: "1rem",
              color: "var(--foreground-muted)",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}
          >
            Actions
          </h2>

          {!authenticated ? (
            <p
              style={{ fontSize: "0.85rem", color: "var(--foreground-muted)" }}
            >
              Connect your wallet to interact with this task.
            </p>
          ) : (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "0.75rem",
              }}
            >
              {/* Claim */}
              {canClaim && (
                <div>
                  <button
                    className="btn-primary"
                    style={{ width: "100%" }}
                    onClick={() => claimTask()}
                    disabled={claimPending || claimConfirming}
                  >
                    {claimPending || claimConfirming ? (
                      <>
                        <Loader2 size={14} className="animate-spin" /> Claiming…
                      </>
                    ) : (
                      "Claim Task · 0.0001 STT bond"
                    )}
                  </button>
                  {claimSuccess && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--green)",
                      }}
                    >
                      ✓ Task claimed!
                    </div>
                  )}
                  {claimError && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--red)",
                      }}
                    >
                      {claimError.message}
                    </div>
                  )}
                </div>
              )}

              {/* Submit Proof */}
              {canSubmitProof && (
                <div>
                  <label
                    style={{
                      fontSize: "0.75rem",
                      color: "var(--foreground-muted)",
                      display: "block",
                      marginBottom: 4,
                    }}
                  >
                    Proof Transaction Hash
                  </label>
                  <input
                    className="input"
                    placeholder="0x…"
                    value={proofInput}
                    onChange={(e) => setProofInput(e.target.value)}
                    style={{ marginBottom: "0.5rem" }}
                  />
                  <button
                    className="btn-primary"
                    style={{ width: "100%" }}
                    onClick={() => submitProof(proofInput as `0x${string}`)}
                    disabled={
                      proofPending ||
                      proofConfirming ||
                      !proofInput.startsWith("0x")
                    }
                  >
                    {proofPending || proofConfirming ? (
                      <>
                        <Loader2 size={14} className="animate-spin" />{" "}
                        Submitting…
                      </>
                    ) : (
                      "Submit Proof"
                    )}
                  </button>
                  {proofSuccess && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--green)",
                      }}
                    >
                      ✓ Proof submitted!
                    </div>
                  )}
                  {proofError && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--red)",
                      }}
                    >
                      {proofError.message}
                    </div>
                  )}
                </div>
              )}

              {/* Finalize */}
              {isFinalizableBool && (
                <div>
                  <button
                    className="btn-primary"
                    style={{ width: "100%" }}
                    onClick={() => finalizeExecution()}
                    disabled={finPending || finConfirming}
                  >
                    <CheckCircle size={15} />
                    {finPending || finConfirming ? (
                      <>
                        <Loader2 size={14} className="animate-spin" />{" "}
                        Finalizing…
                      </>
                    ) : (
                      "Finalize Execution"
                    )}
                  </button>
                  {finSuccess && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--green)",
                      }}
                    >
                      ✓ Finalized! Bounty released.
                    </div>
                  )}
                </div>
              )}

              {/* Dispute */}
              {isPoster && isDisputableBool && (
                <div>
                  <button
                    className="btn-danger"
                    style={{ width: "100%" }}
                    onClick={() => disputeExecution()}
                    disabled={dispPending || dispConfirming}
                  >
                    <AlertTriangle size={15} />
                    {dispPending || dispConfirming ? (
                      <>
                        <Loader2 size={14} className="animate-spin" /> Raising
                        Dispute…
                      </>
                    ) : (
                      "Dispute Execution"
                    )}
                  </button>
                  <div
                    style={{
                      marginTop: 4,
                      fontSize: "0.7rem",
                      color: "var(--foreground-muted)",
                    }}
                  >
                    1-hour window to challenge execution
                  </div>
                  {dispSuccess && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--red)",
                      }}
                    >
                      ✓ Dispute raised.
                    </div>
                  )}
                </div>
              )}

              {/* Expire */}
              {canExpire && (
                <div>
                  <button
                    className="btn-secondary"
                    style={{ width: "100%" }}
                    onClick={() => expireTask()}
                    disabled={expirePending || expireConfirming}
                  >
                    {expirePending || expireConfirming ? (
                      <>
                        <Loader2 size={14} className="animate-spin" /> Expiring…
                      </>
                    ) : (
                      "Expire Task & Refund Bounty"
                    )}
                  </button>
                  {expireSuccess && (
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: "0.75rem",
                        color: "var(--green)",
                      }}
                    >
                      ✓ Task expired. Bounty refunded.
                    </div>
                  )}
                </div>
              )}

              {/* Proof explorer link */}
              {task.proofHash && (
                <a
                  href={`https://shannon-explorer.mantle.network/tx/${task.proofHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-secondary"
                  style={{ width: "100%", justifyContent: "center" }}
                >
                  <ExternalLink size={14} /> View Proof on Explorer
                </a>
              )}

              {task.status === "Open" && !canClaim && !isPoster && (
                <p
                  style={{
                    fontSize: "0.8rem",
                    color: "var(--foreground-muted)",
                    textAlign: "center",
                  }}
                >
                  {isRegistered
                    ? "This task has already been claimed."
                    : "Register as an agent to claim tasks."}
                </p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
