// harness-kit OpenCode adapter. OpenCode loads project plugins from
// .opencode/plugins/ and gives them session-aware tool/shell hooks. Policy stays
// in the portable Bash hooks; this file only translates payloads and outcomes.
// Verified against https://opencode.ai/docs/plugins/ and the published plugin
// type surface on 2026-08-11.
import { spawn } from "node:child_process"
import { join } from "node:path"

const WRITE_TOOLS = new Set(["edit", "write", "multiedit", "patch", "apply_patch"])
const SECRET_TOOLS = new Set(["read", "grep", "glob", "bash", "shell", ...WRITE_TOOLS])
const MAX_HOOK_OUTPUT_BYTES = 64 * 1024

function normalizedPayload(input, args = {}) {
  const tool = String(input?.tool || "")
  const filePath = args.file_path ?? args.filePath ?? args.path
  const toolInput = { ...args }
  if (typeof filePath === "string" && filePath.length > 0) toolInput.file_path = filePath
  return {
    session_id: typeof input?.sessionID === "string" ? input.sessionID : undefined,
    tool_name: tool,
    tool_input: toolInput,
  }
}

function hookRunner(directory, input) {
  return (script, payload) => new Promise((resolve) => {
    const configured = Number.parseInt(process.env.HARNESS_HOOK_TIMEOUT_MS || "5000", 10)
    const timeout = Number.isInteger(configured) && configured > 0 && configured <= 30000 ? configured : 5000
    let child
    try {
      child = spawn("bash", [join(directory, "scripts/harness/hooks", script)], {
        cwd: directory,
        detached: process.platform !== "win32",
        env: {
          ...process.env,
          HARNESS_PROVIDER: "opencode",
          ...(input?.sessionID ? { HARNESS_SESSION_ID: input.sessionID } : {}),
        },
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
      })
    } catch {
      resolve({ status: 0, stdout: "", stderr: "" })
      return
    }

    const stdout = { chunks: [], bytes: 0 }
    const stderr = { chunks: [], bytes: 0 }
    let settled = false
    let stopping = false
    let timer
    const capture = (target, chunk) => {
      const remaining = MAX_HOOK_OUTPUT_BYTES - target.bytes
      if (remaining <= 0) return
      const kept = chunk.length > remaining ? chunk.subarray(0, remaining) : chunk
      target.chunks.push(kept)
      target.bytes += kept.length
    }
    const captured = (target) => Buffer.concat(target.chunks, target.bytes).toString("utf8")
    const finish = (status = 0) => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      resolve({ status, stdout: captured(stdout), stderr: captured(stderr) })
    }
    const stopTree = () => {
      if (stopping) return
      stopping = true
      child.stdin?.destroy()
      child.stdout?.destroy()
      child.stderr?.destroy()
      if (!child.pid) return
      const killChild = () => {
        // Native Node has no portable Windows process-tree kill primitive.
        // If taskkill itself is unavailable, terminate the direct Bash child
        // as a best-effort fail-open fallback; the normal /T path owns tree cleanup.
        try { child.kill("SIGKILL") } catch { /* already gone */ }
      }
      if (process.platform === "win32") {
        try {
          const killer = spawn(process.env.HARNESS_TASKKILL_COMMAND || "taskkill", ["/PID", String(child.pid), "/T", "/F"], {
            stdio: "ignore",
            windowsHide: true,
          })
          killer.once("error", killChild)
          killer.once("close", (status) => { if (status !== 0) killChild() })
          killer.unref()
        } catch {
          killChild()
        }
      } else {
        try { process.kill(-child.pid, "SIGKILL") }
        catch { killChild() }
      }
      child.unref()
    }

    child.stdout.on("data", (chunk) => capture(stdout, chunk))
    child.stderr.on("data", (chunk) => capture(stderr, chunk))
    // A stdin write error (EPIPE) only means the hook stopped reading its
    // payload — a hook that denies before draining stdin is the normal way to
    // provoke it. It says nothing about the verdict, so swallow it and let the
    // close handler report the real exit status. Killing the child here would
    // turn an explicit exit 2 into an allow, the one direction this protocol
    // must never take; the timeout below still bounds a genuinely hung hook.
    child.stdin.on("error", () => {})
    child.on("error", () => { stopTree(); finish() })
    child.on("close", (status, signal) => {
      // Adapter/process failures are observability failures, not policy
      // decisions. Only an explicit hook exit 2 may block the provider.
      finish(signal ? 0 : (typeof status === "number" ? status : 0))
    })
    timer = setTimeout(() => {
      stopTree()
      finish()
    }, timeout)
    // Same reasoning as the stdin error handler: a failed write must not
    // decide the verdict. Let close or the timeout settle this call.
    try { child.stdin.end(`${JSON.stringify(payload)}\n`) }
    catch { /* hook is not reading stdin; its exit status still governs */ }
  })
}

function message(result) {
  return String(result.stderr || result.stdout || "harness-kit hook denied the tool call").trim()
}

// OpenCode hands the tool arguments to tool.execute.before on its second
// parameter and does NOT repeat them on tool.execute.after, whose second
// parameter carries the tool result instead. Carry them across keyed by
// callID, or the after-hook builds an empty tool_input and every path-driven
// hook (format.sh) silently no-ops. Only write tools are ever replayed and
// each entry is consumed once; the cap bounds a call that never completes.
const MAX_PENDING_ARGS = 256

export function createHarnessKitHooks({ directory }, runOverride) {
  const contextualized = new Set()
  const pendingArgs = new Map()
  const run = async (script, payload, input) => {
    try {
      return await (runOverride ? runOverride(script, payload, input) : hookRunner(directory, input)(script, payload))
    } catch {
      return { status: 0, stdout: "", stderr: "" }
    }
  }

  return {
    // harness-hook: tool.execute.before guard-secrets.sh
    // harness-hook: tool.execute.before guard-config.sh
    "tool.execute.before": async (input, output) => {
      const tool = String(input?.tool || "").toLowerCase()
      const args = output?.args || {}
      const payload = normalizedPayload(input, args)
      if (WRITE_TOOLS.has(tool) && input?.callID) {
        if (pendingArgs.size >= MAX_PENDING_ARGS) pendingArgs.clear()
        pendingArgs.set(input.callID, args)
      }
      if (SECRET_TOOLS.has(tool)) {
        const result = await run("guard-secrets.sh", payload, input)
        if (result.status === 2) throw new Error(message(result))
      }
      if (WRITE_TOOLS.has(tool)) {
        const result = await run("guard-config.sh", payload, input)
        if (result.status === 2) throw new Error(message(result))
      }
    },

    // harness-hook: tool.execute.after format.sh
    "tool.execute.after": async (input, output) => {
      const tool = String(input?.tool || "").toLowerCase()
      if (!WRITE_TOOLS.has(tool)) return
      const carried = input?.callID ? pendingArgs.get(input.callID) : undefined
      if (input?.callID) pendingArgs.delete(input.callID)
      const payload = normalizedPayload(input, carried || input?.args || {})
      const result = await run("format.sh", payload, input)
      const feedback = result.status === 2 ? message(result) : ""
      if (feedback) output.output = [output.output, feedback].filter(Boolean).join("\n\n")
    },

    // OpenCode supplies the exact session for each shell call, avoiding a
    // shared last-writer state file when parent and subagent sessions overlap.
    "shell.env": async (input, output) => {
      if (typeof input?.sessionID === "string" && input.sessionID.length > 0) {
        output.env.HARNESS_SESSION_ID = input.sessionID
      }
      output.env.HARNESS_PROVIDER = "opencode"
    },

    // harness-hook: experimental.chat.system.transform session-context.sh
    "experimental.chat.system.transform": async (input, output) => {
      const sessionID = typeof input?.sessionID === "string" ? input.sessionID : ""
      if (!sessionID || contextualized.has(sessionID)) return
      contextualized.add(sessionID)
      const payload = { session_id: sessionID, hook_event_name: "SessionStart" }
      const result = await run("session-context.sh", payload, input)
      const context = String(result.stdout || "").trim()
      if (context) output.system.push(context)
    },
  }
}

export const HarnessKit = async (context) => createHarnessKitHooks(context)
