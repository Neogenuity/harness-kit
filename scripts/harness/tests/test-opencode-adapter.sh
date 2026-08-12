#!/usr/bin/env bash
# Regression tests for the OpenCode project-plugin adapter. The production file
# is ESM; copy it under a temporary type=module package so stock Node can import
# it without requiring OpenCode/Bun on the shipped test host.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PLUGIN_SRC="$ROOT/providers/opencode/plugins/harness-kit.js"
[ -f "$PLUGIN_SRC" ] || PLUGIN_SRC="$ROOT/.opencode/plugins/harness-kit.js"
[ -f "$PLUGIN_SRC" ] || { echo "SKIP: OpenCode adapter is not installed in this provider set"; exit 0; }
if command -v node >/dev/null 2>&1; then
    RUNTIME=(node --input-type=module)
elif command -v bun >/dev/null 2>&1; then
    RUNTIME=(bun run -)
else
    echo "FAIL: OpenCode adapter is installed but neither node nor bun can validate its executable wiring" >&2
    exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-opencode-adapter.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/module"
cp "$PLUGIN_SRC" "$WORK/module/harness-kit.js"
printf '%s\n' '{"type":"module"}' > "$WORK/module/package.json"
mkdir -p "$WORK/hang/scripts/harness/hooks"
cat > "$WORK/hang/scripts/harness/hooks/guard-secrets.sh" <<'HOOK'
#!/usr/bin/env bash
sleep 10
exit 2
HOOK
chmod +x "$WORK/hang/scripts/harness/hooks/guard-secrets.sh"

PLUGIN_PATH="$WORK/module/harness-kit.js"
TEMPLATE_ROOT_ENV="$ROOT"
HANG_ROOT_ENV="$WORK/hang"
if command -v cygpath >/dev/null 2>&1; then
    # Native Windows Node cannot resolve MSYS /tmp paths or file:///tmp URLs.
    # Mixed paths remain valid to Node and to the Git Bash child it spawns.
    PLUGIN_PATH=$(cygpath -m "$PLUGIN_PATH") || exit 1
    TEMPLATE_ROOT_ENV=$(cygpath -m "$TEMPLATE_ROOT_ENV") || exit 1
    HANG_ROOT_ENV=$(cygpath -m "$HANG_ROOT_ENV") || exit 1
fi

HARNESS_TESTING=1 PLUGIN_PATH="$PLUGIN_PATH" \
    TEMPLATE_ROOT="$TEMPLATE_ROOT_ENV" HANG_ROOT="$HANG_ROOT_ENV" "${RUNTIME[@]}" <<'NODE'
import { pathToFileURL } from "node:url"
const { createHarnessKitHooks } = await import(pathToFileURL(process.env.PLUGIN_PATH).href)

let failures = 0
const ok = (condition, message) => {
  if (condition) console.log(`ok:   ${message}`)
  else { console.error(`FAIL: ${message}`); failures += 1 }
}

const calls = []
const runner = (script, payload) => {
  calls.push({ script, payload })
  if (script === "guard-secrets.sh" && payload.tool_input.file_path === ".env") {
    return { status: 2, stdout: "", stderr: "secret denied" }
  }
  if (script === "format.sh") return { status: 2, stdout: "", stderr: "lint feedback" }
  if (script === "session-context.sh") return { status: 0, stdout: "Branch: demo (clean)\n", stderr: "" }
  return { status: 0, stdout: "", stderr: "" }
}

const hooks = createHarnessKitHooks({ directory: process.env.TEMPLATE_ROOT }, runner)
let denied = false
try {
  await hooks["tool.execute.before"](
    { tool: "read", sessionID: "session-a" },
    { args: { filePath: ".env" } },
  )
} catch (error) {
  denied = error.message.includes("secret denied")
}
ok(denied, "pre-tool exit 2 becomes an OpenCode blocking error")
ok(
  calls[0]?.payload?.tool_input?.file_path === ".env" && calls[0]?.payload?.session_id === "session-a",
  "camelCase OpenCode paths and session ids normalize for portable hooks",
)

calls.length = 0
await hooks["tool.execute.before"](
  { tool: "edit", sessionID: "session-b" },
  { args: { filePath: "src/app.js" } },
)
ok(
  calls.map((call) => call.script).join(",") === "guard-secrets.sh,guard-config.sh",
  "write tools traverse both secret and mechanism guards",
)

const output = { output: "edit complete" }
await hooks["tool.execute.after"](
  { tool: "edit", sessionID: "session-b", args: { filePath: "src/app.js" } },
  output,
)
ok(output.output.includes("edit complete") && output.output.includes("lint feedback"), "post-edit lint feedback reaches the model output")

const shell = { env: {} }
await hooks["shell.env"]({ sessionID: "session-c", cwd: process.cwd() }, shell)
ok(
  shell.env.HARNESS_SESSION_ID === "session-c" && shell.env.HARNESS_PROVIDER === "opencode",
  "shell hook injects concurrency-safe session/provider attribution",
)

const system = { system: [] }
await hooks["experimental.chat.system.transform"]({ sessionID: "session-d" }, system)
await hooks["experimental.chat.system.transform"]({ sessionID: "session-d" }, system)
ok(system.system.length === 1 && system.system[0].includes("Branch: demo"), "session context is injected once per session")
const sessionless = { system: [] }
calls.length = 0
await hooks["experimental.chat.system.transform"]({}, sessionless)
ok(sessionless.system.length === 0 && calls.length === 0, "sessionless transforms do not inject unattributable context")

process.env.HARNESS_HOOK_TIMEOUT_MS = "50"
const hung = createHarnessKitHooks({ directory: process.env.HANG_ROOT })
const hungStarted = Date.now()
let hungDenied = false
try {
  await hung["tool.execute.before"](
    { tool: "read", sessionID: "session-hung" },
    { args: { filePath: ".env" } },
  )
} catch { hungDenied = true }
ok(!hungDenied && Date.now() - hungStarted < 2000, "hung child hooks time out and fail open")
delete process.env.HARNESS_HOOK_TIMEOUT_MS

// Exercise the real child-process path once: the portable secret guard must
// block a read even though OpenCode itself is not installed on this host.
const real = createHarnessKitHooks({ directory: process.env.TEMPLATE_ROOT })
denied = false
try {
  await real["tool.execute.before"](
    { tool: "read", sessionID: "session-real" },
    { args: { filePath: ".env" } },
  )
} catch (error) {
  denied = error.message.includes("guard-secrets.sh")
}
ok(denied, "adapter executes the real portable guard and propagates its denial")

if (failures) process.exit(1)
console.log("PASSED: all OpenCode adapter cases")
NODE
