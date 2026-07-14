#!/usr/bin/env node
import { createInterface } from "node:readline";

const lines = createInterface({ input: process.stdin });
const threads = new Map();
let turnCounter = 0;

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

lines.on("line", (line) => {
  const message = JSON.parse(line);
  const id = message.id;

  if (message.method === "initialize") {
    send({
      id,
      result: {
        platformFamily: process.platform,
        platformOs: process.platform,
      },
    });
    return;
  }

  if (message.method === "initialized") {
    send({ method: "server/ready", params: {} });
    return;
  }

  if (message.method === "thread/start") {
    const thread = { id: "thr_fake", name: "[test] Fake thread", cwd: message.params?.cwd || "", turns: [] };
    threads.set(thread.id, thread);
    send({ id, result: { thread } });
    send({ method: "thread/started", params: { thread } });
    return;
  }

  if (message.method === "thread/resume") { send({ id, result: { thread: threads.get(message.params.threadId) || { id: message.params.threadId } } }); return; }
  if (message.method === "thread/list") { send({ id, result: { data: [...threads.values()] } }); return; }
  if (message.method === "thread/read") { send({ id, result: { thread: threads.get(message.params.threadId) || { id: message.params.threadId, turns: [] } } }); return; }
  if (message.method === "model/list") { send({ id, result: { data: [{ id: "fake", model: "fake", displayName: "Fake Model", defaultReasoningEffort: "low", supportedReasoningEfforts: [{ reasoningEffort: "low", description: "Fast" }], inputModalities: ["text", "image"], isDefault: true, hidden: false }, { id: "internal", model: "internal", displayName: "Internal", hidden: true }] } }); return; }
  if (message.method === "account/rateLimits/read") { send({ id, result: { rateLimits: {} } }); return; }
  if (message.method === "thread/compact/start") { send({ id, result: {} }); return; }

  if (message.method === "turn/start") {
    const thread = threads.get(message.params.threadId);
    const turnId = `turn_fake_${++turnCounter}`;
    const text = message.params.input?.find((item) => item.type === "text")?.text || "";
    const shouldFail = text === "FAIL_TEST";
    const assistant = "Fake Codex app-server response.";
    const items = [{ id: `user_${turnCounter}`, type: "userMessage", content: message.params.input }];
    if (!shouldFail) items.push({ id: `assistant_${turnCounter}`, type: "agentMessage", text: assistant });
    if (thread) thread.turns.push({ id: turnId, status: shouldFail ? "failed" : "completed", items });
    send({ id, result: { turn: { id: turnId } } });
    send({ method: "thread/settings/updated", params: { threadId: message.params.threadId, threadSettings: { model: message.params.model || "fake", effort: message.params.effort || "low", approvalPolicy: message.params.approvalPolicy || "on-request", approvalsReviewer: message.params.approvalsReviewer || "user", cwd: thread?.cwd || "", modelProvider: "openai", collaborationMode: { mode: "default", settings: {} }, sandboxPolicy: { type: "workspaceWrite" } } } });
    send({ method: "turn/started", params: { threadId: message.params.threadId, turn: { id: turnId, status: "inProgress" } } });
    if (shouldFail) {
      send({ method: "error", params: { threadId: message.params.threadId, turnId, willRetry: false, error: { message: "Synthetic Codex failure" } } });
      send({ method: "turn/completed", params: { threadId: message.params.threadId, turn: { id: turnId, status: "failed", error: { message: "Synthetic Codex failure" } } } });
      return;
    }
    send({
      method: "item/agentMessage/delta",
      params: { threadId: message.params.threadId, turnId, delta: assistant },
    });
    send({ method: "turn/completed", params: { threadId: message.params.threadId, turn: { id: turnId, status: "completed" } } });
    return;
  }

  if (message.method === "turn/steer" || message.method === "turn/interrupt") {
    send({ id, result: {} });
    return;
  }

  if (id !== undefined) {
    send({ id, error: { code: -32601, message: `Unknown method: ${message.method}` } });
  }
});
