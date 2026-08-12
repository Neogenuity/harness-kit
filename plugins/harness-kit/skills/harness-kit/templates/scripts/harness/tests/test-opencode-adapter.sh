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
( printf 'ready\n' > "$HARNESS_TIMEOUT_READY"; sleep 1; printf 'descendant survived\n' > "$HARNESS_TIMEOUT_MARKER" ) &
sleep 10
exit 2
HOOK
chmod +x "$WORK/hang/scripts/harness/hooks/guard-secrets.sh"
for fixture in early nodrain flood fallback; do
    mkdir -p "$WORK/$fixture/scripts/harness/hooks"
done
cat > "$WORK/early/scripts/harness/hooks/guard-secrets.sh" <<'HOOK'
#!/usr/bin/env bash
exit 0
HOOK
# Denies WITHOUT draining stdin. With a payload larger than the pipe buffer the
# adapter's stdin write cannot complete, and an EPIPE there must not be allowed
# to downgrade this explicit exit 2 into an allow.
cat > "$WORK/nodrain/scripts/harness/hooks/guard-secrets.sh" <<'HOOK'
#!/usr/bin/env bash
echo "nodrain denied" >&2
exit 2
HOOK
cat > "$WORK/flood/scripts/harness/hooks/guard-secrets.sh" <<'HOOK'
#!/usr/bin/env bash
i=0
while [ "$i" -lt 2048 ]; do
    printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
    i=$((i + 1))
done
exit 2
HOOK
cat > "$WORK/fallback/scripts/harness/hooks/guard-secrets.sh" <<'HOOK'
#!/usr/bin/env bash
printf 'ready\n' > "$HARNESS_TIMEOUT_READY"
sleep 1
printf 'parent survived\n' > "$HARNESS_TIMEOUT_MARKER"
exit 2
HOOK
chmod +x "$WORK/early/scripts/harness/hooks/guard-secrets.sh" \
    "$WORK/nodrain/scripts/harness/hooks/guard-secrets.sh" \
    "$WORK/flood/scripts/harness/hooks/guard-secrets.sh" \
    "$WORK/fallback/scripts/harness/hooks/guard-secrets.sh"

PLUGIN_PATH="$WORK/module/harness-kit.js"
TEMPLATE_ROOT_ENV="$ROOT"
HANG_ROOT_ENV="$WORK/hang"
HANG_MARKER_ENV="$WORK/descendant-survived"
HANG_READY_ENV="$WORK/descendant-launched"
EARLY_ROOT_ENV="$WORK/early"
NODRAIN_ROOT_ENV="$WORK/nodrain"
FLOOD_ROOT_ENV="$WORK/flood"
FALLBACK_ROOT_ENV="$WORK/fallback"
FALLBACK_MARKER_ENV="$WORK/parent-survived"
FALLBACK_READY_ENV="$WORK/fallback-launched"
if command -v cygpath >/dev/null 2>&1; then
    # Native Windows Node cannot resolve MSYS /tmp paths or file:///tmp URLs.
    # Mixed paths remain valid to Node and to the Git Bash child it spawns.
    PLUGIN_PATH=$(cygpath -m "$PLUGIN_PATH") || exit 1
    TEMPLATE_ROOT_ENV=$(cygpath -m "$TEMPLATE_ROOT_ENV") || exit 1
    HANG_ROOT_ENV=$(cygpath -m "$HANG_ROOT_ENV") || exit 1
    HANG_MARKER_ENV=$(cygpath -m "$HANG_MARKER_ENV") || exit 1
    HANG_READY_ENV=$(cygpath -m "$HANG_READY_ENV") || exit 1
    EARLY_ROOT_ENV=$(cygpath -m "$EARLY_ROOT_ENV") || exit 1
    NODRAIN_ROOT_ENV=$(cygpath -m "$NODRAIN_ROOT_ENV") || exit 1
    FLOOD_ROOT_ENV=$(cygpath -m "$FLOOD_ROOT_ENV") || exit 1
    FALLBACK_ROOT_ENV=$(cygpath -m "$FALLBACK_ROOT_ENV") || exit 1
    FALLBACK_MARKER_ENV=$(cygpath -m "$FALLBACK_MARKER_ENV") || exit 1
    FALLBACK_READY_ENV=$(cygpath -m "$FALLBACK_READY_ENV") || exit 1
fi

HARNESS_TESTING=1 PLUGIN_PATH="$PLUGIN_PATH" \
    TEMPLATE_ROOT="$TEMPLATE_ROOT_ENV" HANG_ROOT="$HANG_ROOT_ENV" \
    HANG_MARKER="$HANG_MARKER_ENV" HANG_READY="$HANG_READY_ENV" \
    EARLY_ROOT="$EARLY_ROOT_ENV" NODRAIN_ROOT="$NODRAIN_ROOT_ENV" \
    FLOOD_ROOT="$FLOOD_ROOT_ENV" FALLBACK_ROOT="$FALLBACK_ROOT_ENV" \
    FALLBACK_MARKER="$FALLBACK_MARKER_ENV" FALLBACK_READY="$FALLBACK_READY_ENV" \
    "${RUNTIME[@]}" <<'NODE'
import { existsSync } from "node:fs"
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

const asyncHooks = createHarnessKitHooks({ directory: process.env.TEMPLATE_ROOT }, async () => {
  await new Promise((resolve) => setTimeout(resolve, 5))
  return { status: 2, stdout: "", stderr: "async secret denied" }
})
denied = false
try {
  await asyncHooks["tool.execute.before"](
    { tool: "read", sessionID: "session-async" },
    { args: { filePath: ".env" } },
  )
} catch (error) {
  denied = error.message.includes("async secret denied")
}
ok(denied, "Promise-returning hook runners preserve explicit denials")

const early = createHarnessKitHooks({ directory: process.env.EARLY_ROOT })
let earlyFailed = false
try {
  await early["tool.execute.before"](
    { tool: "read", sessionID: "session-early" },
    { args: { filePath: ".env", payload: "x".repeat(4 * 1024 * 1024) } },
  )
} catch { earlyFailed = true }
ok(!earlyFailed, "early child exit with a large payload fails open without stdin errors")

// The counterpart that matters: same unread-stdin race, but the hook exits 2.
// A failed stdin write must never downgrade an explicit deny to an allow.
const nodrain = createHarnessKitHooks({ directory: process.env.NODRAIN_ROOT })
let nodrainDenied = false
try {
  await nodrain["tool.execute.before"](
    { tool: "read", sessionID: "session-nodrain" },
    { args: { filePath: ".env", payload: "x".repeat(4 * 1024 * 1024) } },
  )
} catch (error) { nodrainDenied = error.message.includes("nodrain denied") }
ok(nodrainDenied, "exit 2 survives a large payload the hook never drains from stdin")

const flood = createHarnessKitHooks({ directory: process.env.FLOOD_ROOT })
let floodMessage = ""
try {
  await flood["tool.execute.before"](
    { tool: "read", sessionID: "session-flood" },
    { args: { filePath: ".env" } },
  )
} catch (error) { floodMessage = error.message }
ok(
  floodMessage.length > 0 && floodMessage.length <= 64 * 1024,
  "hook output is drained but denial feedback remains memory-bounded",
)

calls.length = 0
await hooks["tool.execute.before"](
  { tool: "edit", sessionID: "session-b", callID: "call-b" },
  { args: { filePath: "src/app.js" } },
)
ok(
  calls.map((call) => call.script).join(",") === "guard-secrets.sh,guard-config.sh",
  "write tools traverse both secret and mechanism guards",
)

// OpenCode gives args to the BEFORE hook only; the after hook's second
// parameter is the tool result. Passing args on `input` here would fake a
// payload the runtime never sends and hide an empty tool_input.
calls.length = 0
const output = { title: "edit", output: "edit complete", metadata: {} }
await hooks["tool.execute.after"](
  { tool: "edit", sessionID: "session-b", callID: "call-b" },
  output,
)
ok(output.output.includes("edit complete") && output.output.includes("lint feedback"), "post-edit lint feedback reaches the model output")
ok(
  calls.find((call) => call.script === "format.sh")?.payload?.tool_input?.file_path === "src/app.js",
  "after-hook carries the before-hook args, so format.sh sees the edited path",
)

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
let concurrentCalls = 0
const concurrent = createHarnessKitHooks({ directory: process.env.TEMPLATE_ROOT }, async () => {
  concurrentCalls += 1
  await new Promise((resolve) => setTimeout(resolve, 25))
  return { status: 0, stdout: "Branch: concurrent\n", stderr: "" }
})
const concurrentSystem = { system: [] }
await Promise.all([
  concurrent["experimental.chat.system.transform"]({ sessionID: "session-concurrent" }, concurrentSystem),
  concurrent["experimental.chat.system.transform"]({ sessionID: "session-concurrent" }, concurrentSystem),
])
ok(concurrentCalls === 1 && concurrentSystem.system.length === 1, "concurrent transforms inject context once per session")
const sessionless = { system: [] }
calls.length = 0
await hooks["experimental.chat.system.transform"]({}, sessionless)
ok(sessionless.system.length === 0 && calls.length === 0, "sessionless transforms do not inject unattributable context")

process.env.HARNESS_HOOK_TIMEOUT_MS = "500"
process.env.HARNESS_TIMEOUT_MARKER = process.env.HANG_MARKER
process.env.HARNESS_TIMEOUT_READY = process.env.HANG_READY
const hung = createHarnessKitHooks({ directory: process.env.HANG_ROOT })
const hungStarted = Date.now()
let hungDenied = false
try {
  await hung["tool.execute.before"](
    { tool: "read", sessionID: "session-hung" },
    { args: { filePath: ".env" } },
  )
} catch { hungDenied = true }
ok(
  !hungDenied && Date.now() - hungStarted < 2000 && existsSync(process.env.HANG_READY),
  "a started hung child hook times out and fails open",
)
await new Promise((resolve) => setTimeout(resolve, 1500))
ok(!existsSync(process.env.HANG_MARKER), "hook timeout terminates descendant processes")
delete process.env.HARNESS_HOOK_TIMEOUT_MS
delete process.env.HARNESS_TIMEOUT_MARKER
delete process.env.HARNESS_TIMEOUT_READY

if (process.platform === "win32") {
  process.env.HARNESS_HOOK_TIMEOUT_MS = "500"
  process.env.HARNESS_TIMEOUT_MARKER = process.env.FALLBACK_MARKER
  process.env.HARNESS_TIMEOUT_READY = process.env.FALLBACK_READY
  process.env.HARNESS_TASKKILL_COMMAND = "harness-kit-missing-taskkill"
  const fallback = createHarnessKitHooks({ directory: process.env.FALLBACK_ROOT })
  const fallbackStarted = Date.now()
  await fallback["tool.execute.before"](
    { tool: "read", sessionID: "session-fallback" },
    { args: { filePath: ".env" } },
  )
  await new Promise((resolve) => setTimeout(resolve, 1500))
  ok(
    Date.now() - fallbackStarted < 3000 && existsSync(process.env.FALLBACK_READY)
      && !existsSync(process.env.FALLBACK_MARKER),
    "missing taskkill safely falls back to direct-child termination",
  )
  delete process.env.HARNESS_HOOK_TIMEOUT_MS
  delete process.env.HARNESS_TIMEOUT_MARKER
  delete process.env.HARNESS_TIMEOUT_READY
  delete process.env.HARNESS_TASKKILL_COMMAND
}

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
