#!/usr/bin/env bash
# Provider-neutral trace normalization and deterministic trajectory metrics.
# Source this file. It never invokes a provider and never changes eval scoring.

# eval_normalize_trace <claude|codex> <provider-jsonl>
# Emits trace-event.v1 JSONL. Malformed provider rows are ignored; an unknown
# provider or missing jq is an explicit caller error.
eval_normalize_trace() {
    local provider="${1:-}" transcript="${2:-}"
    command -v jq >/dev/null 2>&1 || { echo "trace-lib: jq is required" >&2; return 1; }
    [ -r "$transcript" ] || { echo "trace-lib: transcript is not readable: $transcript" >&2; return 1; }
    case "$provider" in claude|codex) ;; *) echo "trace-lib: provider must be claude or codex" >&2; return 64 ;; esac
    jq -Rsc --arg provider "$provider" '
      def clean: with_entries(select(.value != null and .value != ""));
      def stamp($r): if ($r.timestamp? | type) == "string" then $r.timestamp else null end;
      [split("\n")[] | select(length > 0) | (fromjson? // empty)
       | select(type == "object")] as $rows
      | (reduce ($rows[] | select(.type == "assistant") | (try .message.content[]? catch empty) | select(type == "object")
                    | select(.type == "tool_use" and (.id|type) == "string")) as $t
             ({}; .[$t.id] = {name:($t.name // "unknown"),input:(if ($t.input|type)=="object" then $t.input else {} end)})) as $claude_tools
      | (if $provider == "claude" then
          [ $rows[] as $r
            | if $r.type == "system" and $r.subtype == "init" then
                {ts:stamp($r),type:"session.started",attributes:({session_id:($r.session_id // null)}|clean)}
              elif $r.type == "assistant" then
                ((try $r.message.content[]? catch empty) | select(type == "object")
                 | select(.type == "tool_use" and (.id|type) == "string")
                 | . as $t
                 | (if ($t.input|type)=="object" then $t.input else {} end) as $input
                 | if ($t.name == "Read" or $t.name == "Grep" or $t.name == "Glob"
                       or $t.name == "Edit" or $t.name == "Write" or $t.name == "NotebookEdit") then
                     {ts:stamp($r),type:"tool.started",attributes:({name:$t.name,path:($input.file_path // $input.path // null),pattern:($input.pattern // null),tool_id:$t.id}|clean)}
                   elif $t.name == "Bash" then
                     {ts:stamp($r),type:"command.started",attributes:({command:$input.command,tool_id:$t.id}|clean)}
                   else
                     {ts:stamp($r),type:"tool.started",attributes:({name:$t.name,tool_id:$t.id}|clean)}
                   end)
              elif $r.type == "user" then
                ((try $r.message.content[]? catch empty) | select(type == "object")
                 | select(.type == "tool_result" and (.tool_use_id|type) == "string")
                 | . as $t | ($claude_tools[$t.tool_use_id] // {name:"unknown",input:{}}) as $meta
                 | $meta.name as $name
                 | (if ($t.is_error|type) == "boolean" then ($t.is_error|not)
                    elif $t.is_error == null then true else null end) as $ok
                 | if $name == "Bash" then
                     {ts:stamp($r),type:"command.finished",attributes:({command:($meta.input.command // null),tool_id:$t.tool_use_id,success:$ok}|clean)}
                   elif $ok and $name == "Read" then
                     {ts:stamp($r),type:"file.read",attributes:({path:($meta.input.file_path // null),tool_id:$t.tool_use_id}|clean)}
                   elif $ok and ($name == "Grep" or $name == "Glob") then
                     {ts:stamp($r),type:"file.search",attributes:({path:($meta.input.path // null),pattern:($meta.input.pattern // null),tool_id:$t.tool_use_id}|clean)}
                   elif $ok and ($name == "Edit" or $name == "Write" or $name == "NotebookEdit") then
                     {ts:stamp($r),type:"file.write",attributes:({path:($meta.input.file_path // null),tool_id:$t.tool_use_id}|clean)}
                   else
                     {ts:stamp($r),type:"tool.finished",attributes:({name:$name,path:($meta.input.file_path // $meta.input.path // null),tool_id:$t.tool_use_id,success:$ok}|clean)}
                   end)
              elif $r.type == "result" then
                {ts:stamp($r),type:"session.finished",attributes:({outcome:($r.subtype // null),is_error:($r.is_error // null)}|clean)}
              else empty end ]
        else
          [ $rows[] as $r
            | (if ($r.item? | type) == "object" then ($r.item.type // $r.item.item_type // "") else "" end) as $kind
            | if $r.type == "thread.started" then
                {ts:stamp($r),type:"session.started",attributes:({session_id:($r.thread_id // null)}|clean)}
              elif $r.type == "item.started" and $kind == "command_execution" then
                {ts:stamp($r),type:"command.started",attributes:({command:($r.item.command // null),tool_id:($r.item.id // null)}|clean)}
              elif $r.type == "item.completed" and $kind == "command_execution" then
                (if ($r.item.exit_code|type) == "number" then $r.item.exit_code else null end) as $exit
                | {ts:stamp($r),type:"command.finished",attributes:({command:($r.item.command // null),tool_id:($r.item.id // null),exit_code:$exit,success:(if $exit == null then null else $exit == 0 end)}|clean)}
              elif $r.type == "item.completed" and $kind == "file_change" then
                ((if $r.item.changes == null then [{path:($r.item.path // null),kind:null}]
                  elif ($r.item.changes|type) == "array" then $r.item.changes else [] end)[]
                 | select(type == "object")
                 | {ts:stamp($r),type:"file.write",attributes:({path:.path,kind:(.kind // null),tool_id:($r.item.id // null)}|clean)})
              elif $r.type == "item.started" and $kind != "" and ($kind != "agent_message" and $kind != "reasoning") then
                {ts:stamp($r),type:"tool.started",attributes:({name:$kind,tool_id:($r.item.id // null)}|clean)}
              elif $r.type == "item.completed" and $kind != "" and ($kind != "agent_message" and $kind != "reasoning" and $kind != "file_change") then
                {ts:stamp($r),type:"tool.finished",attributes:({name:$kind,tool_id:($r.item.id // null)}|clean)}
              elif $r.type == "turn.completed" then
                {ts:stamp($r),type:"session.finished",attributes:{outcome:"completed"}}
              else empty end ]
        end)
      | to_entries[]
      | {version:1,seq:(.key+1),ts:.value.ts,provider:$provider,type:.value.type,attributes:.value.attributes}
    ' "$transcript"
}

# eval_trajectory_json <trace-jsonl>
# Emits deterministic observational metrics. They are evidence for authoring
# and review, never an input to task outcome or baseline semantics.
eval_trajectory_json() {
    local trace="${1:-}"
    command -v jq >/dev/null 2>&1 || { echo "trace-lib: jq is required" >&2; return 1; }
    [ -r "$trace" ] || { echo "trace-lib: trace is not readable: $trace" >&2; return 1; }
    jq -Rsc '
      def command_matches($body):
        test("(^|[;&|][[:space:]]*)(?:(?:env[[:space:]]+)?(?:[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*)" + $body + "([[:space:]]|$)"; "i");
      def verification_command:
        command_matches("(?:(?:bash|sh)[[:space:]]+)?(?:\\./)?scripts/harness/(?:verify|check-harness)")
        or command_matches("(?:make|npm|pnpm|yarn)[[:space:]]+(?:run[[:space:]]+)?(?:verify|check-harness)");
      def test_command:
        verification_command
        or command_matches("(?:npm|pnpm|yarn)[[:space:]]+(?:run[[:space:]]+)?test")
        or command_matches("python(?:3)?[[:space:]]+-m[[:space:]]+(?:pytest|unittest)")
        or command_matches("(?:pytest|go[[:space:]]+test|cargo[[:space:]]+test|make[[:space:]]+(?:test|check))")
        or command_matches("(?:bash|sh)[[:space:]]+[^;&|[:space:]]*(?:test[^;&|[:space:]]*\\.sh|tests/[^;&|[:space:]]+)");
      [split("\n")[] | select(length > 0) | (fromjson? // empty)
       | select(.version == 1 and (.seq|type) == "number" and (.type|type) == "string")] as $e
      | [$e[] | select(.type == "file.read")
          | select((.attributes.path|type) == "string")
          | select(.attributes.path | test("(^|/)(AGENTS\\.md|CLAUDE\\.md|GEMINI\\.md|SKILL\\.md|\\.github/copilot-instructions\\.md)$")) | .seq] as $instruction_seq
      | (($instruction_seq|length) > 0) as $instruction_available
      | [$e[] | select(.type == "file.write") | .seq] as $write_seq
      | [$e[] | select(.type == "command.started" or .type == "tool.started")
          | select(.seq < ($instruction_seq|min))
          | select(.type == "command.started" or ((.attributes.name // "") as $name
              | ($name != "Read" and $name != "Grep" and $name != "Glob")))] as $opaque_before_instruction
      | [$e[] | select(.type == "command.started")
          | {seq,command:(if (.attributes.command|type)=="string" then .attributes.command else "" end)}] as $commands
      | [$e[] | select(.type == "command.finished")
          | select((.attributes.success == false) or
              ((.attributes.exit_code|type)=="number" and .attributes.exit_code != 0))
          | {seq,command:(if (.attributes.command|type)=="string" then .attributes.command else "" end)}] as $failures
      | [$e[] | select(.type == "command.finished")
          | select((.attributes.success == true) or
              ((.attributes.exit_code|type)=="number" and .attributes.exit_code == 0))
          | {seq,command:(if (.attributes.command|type)=="string" then .attributes.command else "" end)}] as $successes
      | {version:1,
         events:($e|length),
         instruction_discovery_available:$instruction_available,
         instructions_discovered:(if $instruction_available then true else null end),
         edited_before_instruction_discovery:(if $instruction_available|not then null
           elif ($opaque_before_instruction|length)>0 then null
           elif ($write_seq|length)==0 then false
           elif ($instruction_seq|min) < ($write_seq|min) then false else null end),
         tests_executed:([$commands[] | select(.command | test_command)] | length),
         verification_executed:([$commands[] | select(.command | verification_command)] | length > 0),
         failed_commands:($failures|length),
         recovery_successful:(if ($failures|length)==0 then false
           else any($failures[]; . as $failure
             | any($successes[]; .seq > $failure.seq and .command != "" and .command == $failure.command)) end),
         repeated_reads:([$e[] | select(.type == "file.read" and (.attributes.path|type)=="string") | .attributes.path]
           | sort | group_by(.) | map(select(length > 1) | length - 1) | add // 0),
         repeated_commands:([$commands[].command | select(length > 0)]
           | sort | group_by(.) | map(select(length > 1) | length - 1) | add // 0),
         files_modified:([$e[] | select(.type == "file.write" and (.attributes.path|type)=="string") | .attributes.path] | unique | sort)}
    ' "$trace"
}
