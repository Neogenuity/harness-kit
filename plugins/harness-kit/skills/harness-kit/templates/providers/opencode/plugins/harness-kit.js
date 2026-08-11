// harness-kit OpenCode adapter. OpenCode loads project plugins from
// .opencode/plugins/ and gives them session-aware tool/shell hooks. Policy stays
// in the portable Bash hooks; this file only translates payloads and outcomes.
// Verified against https://opencode.ai/docs/plugins/ and the published plugin
// type surface on 2026-08-11.
import { spawnSync } from "node:child_process"
import { join } from "node:path"

const WRITE_TOOLS = new Set(["edit", "write", "multiedit", "patch", "apply_patch"])
const SECRET_TOOLS = new Set(["read", "grep", "glob", "bash", "shell", ...WRITE_TOOLS])

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
  return (script, payload) => {
    const configured = Number.parseInt(process.env.HARNESS_HOOK_TIMEOUT_MS || "5000", 10)
    const timeout = Number.isInteger(configured) && configured > 0 && configured <= 30000 ? configured : 5000
    let result
    try {
      result = spawnSync("bash", [join(directory, "scripts/harness/hooks", script)], {
        cwd: directory,
        encoding: "utf8",
        timeout,
        env: {
          ...process.env,
          HARNESS_PROVIDER: "opencode",
          ...(input?.sessionID ? { HARNESS_SESSION_ID: input.sessionID } : {}),
        },
        input: `${JSON.stringify(payload)}\n`,
      })
    } catch {
      return { status: 0, stdout: "", stderr: "" }
    }
    // Adapter/process failures are observability failures, not policy
    // decisions. Only an explicit hook exit 2 may block the provider.
    if (result.error || result.signal) return { status: 0, stdout: "", stderr: "" }
    return {
      status: typeof result.status === "number" ? result.status : 0,
      stdout: result.stdout || "",
      stderr: result.stderr || "",
    }
  }
}

function message(result) {
  return String(result.stderr || result.stdout || "harness-kit hook denied the tool call").trim()
}

export function createHarnessKitHooks({ directory }, runOverride) {
  const contextualized = new Set()
  const run = (script, payload, input) =>
    (runOverride ? runOverride(script, payload, input) : hookRunner(directory, input)(script, payload))

  return {
    // harness-hook: tool.execute.before guard-secrets.sh
    // harness-hook: tool.execute.before guard-config.sh
    "tool.execute.before": async (input, output) => {
      const tool = String(input?.tool || "").toLowerCase()
      const payload = normalizedPayload(input, output?.args || {})
      if (SECRET_TOOLS.has(tool)) {
        const result = run("guard-secrets.sh", payload, input)
        if (result.status === 2) throw new Error(message(result))
      }
      if (WRITE_TOOLS.has(tool)) {
        const result = run("guard-config.sh", payload, input)
        if (result.status === 2) throw new Error(message(result))
      }
    },

    // harness-hook: tool.execute.after format.sh
    "tool.execute.after": async (input, output) => {
      const tool = String(input?.tool || "").toLowerCase()
      if (!WRITE_TOOLS.has(tool)) return
      const payload = normalizedPayload(input, input?.args || {})
      const result = run("format.sh", payload, input)
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
      const payload = { session_id: sessionID, hook_event_name: "SessionStart" }
      const result = run("session-context.sh", payload, input)
      const context = String(result.stdout || "").trim()
      if (context) output.system.push(context)
      contextualized.add(sessionID)
    },
  }
}

export const HarnessKit = async (context) => createHarnessKitHooks(context)
