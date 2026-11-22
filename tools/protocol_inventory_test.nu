# In-memory inventory corruption tests. Source protocol_coverage.nu before this.
# No live catalogue/manifest mutation, no repository checkout or network.
let catalogue = (open protocol_coverage.yml)
let inventory = (open protocol_coverage_inventory.yml)

def require-rule [diagnostics: list<record>, rule: string] {
  if $rule not-in ($diagnostics | get rule) {
    error make {msg: $"expected inventory diagnostic ($rule), got ($diagnostics | to json -r)"}
  }
}

let accepted = (protocol inventory diagnostics $catalogue $inventory)
if ($accepted | length) != 0 {
  error make {msg: $"accepted inventory failed: ($accepted | to json -r)"}
}
let reviewed_ids = {
  osc52_clipboard: [windows_terminal.osc52.set windows_terminal.osc52.query_ignored]
  da1_clipboard_write: [windows_terminal.da1.clipboard_write_advertisement]
  osc9_progress: [windows_terminal.osc9.task_progress]
}
for group in ($reviewed_ids | transpose name ids) {
  let observed = ($catalogue.references.windows_terminal.groups | get $group.name | get records | columns | sort)
  if $observed != ($group.ids | sort) {
    error make {msg: $"Windows reference group ($group.name) differs from the reviewed command IDs"}
  }
}
let ghostty_ids = ($catalogue.references.ghostty.groups.osc7501_status.records | columns | sort)
if $ghostty_ids != ([ghostty.osc7501.status_query ghostty.osc7501.status_report] | sort) {
  error make {msg: "Ghostty OSC 7501 group differs from the two reviewed branch IDs"}
}
let kitty_delta_ids = {
  dispatch_osc_program_status: [kitty_delta.osc.program_status]
  indexed_graphics_formats: [kitty_delta.graphics.format_indexed8 kitty_delta.graphics.format_indexed16]
  conemu_cwd_report: [kitty_delta.osc.conemu_cwd]
  kitty_dcs_color_scheme: [kitty_delta.dcs.remote_color_scheme]
  graphics_feature_queries: [kitty_delta.graphics.feature_query]
  transient_usage_hint: [kitty_delta.graphics.usage_hint_transient]
}
for group in ($kitty_delta_ids | transpose name ids) {
  let observed = ($catalogue.references.kitty_delta.groups | get $group.name | get records | columns | sort)
  if $observed != ($group.ids | sort) {
    error make {msg: $"Kitty delta group ($group.name) differs from the reviewed new semantic IDs"}
  }
}

# The pinned reference inventory grew by one independently reviewed
# ExecFailed branch. Guard its exact presence, not merely the group count.
# Pinned iTerm2's OSC selector table also has Linux OSC P and OSC 9.
for id in ["iterm2.osc.linux_palette" "iterm2.osc.user_notification"] {
  if ($catalogue.references.iterm2.groups.tokenTypeForMode.records
    | columns | where $it == $id | length) != 1 {
    error make {msg: $"missing pinned iTerm2 OSC dispatch ($id)"}
  }
}

if ($catalogue.references.iterm2.groups.executeXtermSetKvp.records
  | columns | where $it == "iterm2.osc1337.exec_failed" | length) != 1 {
  error make {msg: "pinned iTerm2 OSC1337 ExecFailed branch missing from approved catalogue"}
}

# Decision metadata is part of the indexed protocol contract, not a note.
let ruling = (protocol decision libvterm.csi.decsgr)
if ($ruling.id != "libvterm.csi.decsgr"
    or $ruling.disposition != adjudicated
    or $ruling.adjudication.wire != "CSI ? 4 m"
    or $ruling.adjudication.winner.protocol != XTQMODKEYS
    or $ruling.adjudication.loser.protocol != DECSGR
    or $ruling.policy.criteria != [protocol_origin exact_effects current_usage implementation_preference protocol_recency]
    or $ruling.policy.implementation_preference != [kitty xterm iterm2 ghostty]) {
  error make {msg: "indexed XTQMODKEYS/DECSGR decision is not machine-discoverable"}
}
let indexed_rulings = (protocol decisions)
let expected_rulings = [
  iterm2.csi.cbt
  iterm2.csi.cha
  iterm2.csi.cnl
  iterm2.csi.cpl
  iterm2.csi.cup
  iterm2.csi.cub
  iterm2.csi.cud
  iterm2.csi.cuf
  iterm2.csi.cuu
  iterm2.csi.cht
  iterm2.csi.dch
  iterm2.csi.ech
  iterm2.csi.hvp
  iterm2.csi.rep
  iterm2.csi.tbc
  iterm2.csi.vpa
  iterm2.osc.bg
  iterm2.osc.cursor
  iterm2.osc.fg
  iterm2.osc.highlight_bg
  iterm2.osc.highlight_fg
  iterm2.osc.palette
  iterm2.osc.palette_reset
  kitty.osc.bg
  kitty.osc.cursor
  kitty.osc.fg
  kitty.osc.highlight_bg
  kitty.osc.highlight_fg
  kitty.osc.palette
  kitty.osc.palette_reset
  libvterm.csi.cbt
  libvterm.csi.cha
  libvterm.csi.cnl
  libvterm.csi.cpl
  libvterm.csi.cup
  libvterm.csi.cub
  libvterm.csi.cud
  libvterm.csi.cuf
  libvterm.csi.cuu
  libvterm.csi.cht
  libvterm.csi.decsgr
  libvterm.csi.dch
  libvterm.csi.ech
  libvterm.csi.hpa
  libvterm.csi.hvp
  libvterm.csi.ich
  libvterm.csi.rep
  libvterm.csi.tbc
  libvterm.csi.vpa
]
if ($indexed_rulings | get id | sort) != ($expected_rulings | sort) {
  error make {msg: "indexed collision decision IDs differ from accepted source-backed rulings"}
}
# Frozen Kitty's REP b and TBC g reject a second numeric operand,
# unlike pinned libvterm/iTerm2 which act on the first. Preserve the
# separate already accepted libvterm-style TBC mode-5 clear-all decision.
for reference in [libvterm iterm2] {
  for command in [
    {name: rep, wire: "CSI 1 ; 9 b", proof: "terminal: pinned Kitty REP rejects excess counts without repeating or disturbing graphics"}
    {name: tbc, wire: "CSI 3 ; 9 g", proof: "terminal: pinned Kitty TBC rejects excess operands while retaining libvterm mode five"}
  ] {
    let id = ($reference + ".csi." + $command.name)
    let decision = (protocol decision $id)
    if ($decision.disposition != adjudicated
        or $decision.adjudication.kind != wire_collision
        or $decision.adjudication.wire != $command.wire
        or $decision.adjudication.winner.owner != kitty
        or $decision.adjudication.loser.owner != $reference
        or $decision.adjudication.proof.symbol != $command.proof) {
      error make {msg: $"pinned REP/TBC admission ruling is not source-backed: ($id)"}
    }
  }
}
# Pinned Kitty admits only one operand for ordinary I/X/P/@. Both pinned
# comparators consume the first even when extras exist. The frozen iTerm2
# catalogue has no separately indexed ICH ID, so don't invent one here.
for reference in [libvterm iterm2] {
  for command in [
    {name: ich, wire: "CSI 1 ; 9 @"}
    {name: cht, wire: "CSI 1 ; 9 I"}
    {name: dch, wire: "CSI 1 ; 9 P"}
    {name: ech, wire: "CSI 1 ; 9 X"}
  ] {
    if $reference == iterm2 and $command.name == ich { continue }
    let id = ($reference + ".csi." + $command.name)
    let ruling = (protocol decision $id)
    if ($ruling.disposition != adjudicated
        or $ruling.adjudication.kind != wire_collision
        or $ruling.adjudication.wire != $command.wire
        or $ruling.adjudication.winner.owner != kitty
        or $ruling.adjudication.loser.owner != $reference
        or $ruling.adjudication.proof.symbol != "terminal: pinned Kitty I X P at reject surplus operands without cell or graphic edits") {
      error make {msg: $"pinned edit/tab admission decision is not source-backed: ($id)"}
    }
  }
}
# Frozen Kitty's eight single-operand directional commands reject extras;
# pinned libvterm and iTerm2 consume the first. Each losing command must
# retain exact evidence and the shared native negative-space proof.
for reference in [libvterm iterm2] {
  for command in [
    {name: cuu, wire: "CSI 1 ; 9 A"}
    {name: cud, wire: "CSI 1 ; 9 B"}
    {name: cuf, wire: "CSI 1 ; 9 C"}
    {name: cub, wire: "CSI 1 ; 9 D"}
    {name: cnl, wire: "CSI 1 ; 9 E"}
    {name: cpl, wire: "CSI 1 ; 9 F"}
    {name: cha, wire: "CSI 1 ; 9 G"}
    {name: hpa, wire: "CSI 1 ; 9 `"}
  ] {
    if $reference == iterm2 and $command.name == hpa { continue }
    let id = ($reference + ".csi." + $command.name)
    let decision = (protocol decision $id)
    if ($decision.disposition != adjudicated
        or $decision.adjudication.kind != wire_collision
        or $decision.adjudication.wire != $command.wire
        or $decision.adjudication.winner.owner != kitty
        or $decision.adjudication.loser.owner != $reference
        or $decision.adjudication.proof.symbol != "terminal: pinned Kitty directional CSI rejects surplus counts without cursor or graphics mutation") {
      error make {msg: $"pinned directional cursor admission decision is not source-backed: ($id)"}
    }
  }
}
# Kitty permits only two CUP/HVP operands. Pinned libvterm/iTerm2
# instead act on the first two; both losers require explicit source pins
# and an unchanged-cursor proof before a strict indexed ruling is accepted.
for reference in [libvterm iterm2] {
  for command in [
    {name: cup, wire: "CSI 3 ; 4 ; 5 H"}
    {name: hvp, wire: "CSI 3 ; 4 ; 5 f"}
  ] {
    let id = ($reference + ".csi." + $command.name)
    let decision = (protocol decision $id)
    if ($decision.disposition != adjudicated
        or $decision.adjudication.kind != wire_collision
        or $decision.adjudication.wire != $command.wire
        or $decision.adjudication.winner.owner != kitty
        or $decision.adjudication.loser.owner != $reference
        or $decision.adjudication.proof.symbol != "terminal: pinned Kitty CUP HVP reject surplus operands without cursor or graphics mutation") {
      error make {msg: $"pinned CUP/HVP arity decision is not source-backed: ($id)"}
    }
  }
}
# Kitty rejects surplus operands on VPA and CBT, while pinned libvterm
# and iTerm2 use the first count and move. Keep each losing source and
# the one native no-mutation regression independently machine-checkable.
for reference in [libvterm iterm2] {
  for command in [
    {name: cbt, wire: "CSI 1 ; 2 Z"}
    {name: vpa, wire: "CSI 3 ; 2 d"}
  ] {
    let id = ($reference + ".csi." + $command.name)
    let decision = (protocol decision $id)
    if ($decision.disposition != adjudicated
        or $decision.adjudication.kind != wire_collision
        or $decision.adjudication.wire != $command.wire
        or $decision.adjudication.winner.owner != kitty
        or $decision.adjudication.loser.owner != $reference
        or $decision.adjudication.proof.symbol != "terminal: pinned Kitty VPA CBT reject excess operands and preserve cursor and graphics") {
      error make {msg: $"pinned cursor admission decision is not source-backed: ($id)"}
    }
  }
}
# Dynamic invalid-color and BEL reply conflicts each have a real winner
# and a separate exact named source-level Zig regression.
for reference in [kitty iterm2] {
  for family in [fg bg cursor highlight_bg highlight_fg] {
    let id = ($reference + ".osc." + $family)
    let ruling = (protocol decision $id)
    if ($ruling.id != $id
        or $ruling.disposition != adjudicated
        or $ruling.adjudication.kind != wire_collision
        or $ruling.adjudication.winner.owner != xterm
        or $ruling.adjudication.loser.owner != $reference
        or ($ruling.adjudication.reason | str trim | is-empty)) {
      error make {msg: $"source owner or evidence missing from dynamic-color ruling ($id)"}
    }
    let expected_test = if $reference == kitty {
      "xterm dynamic OSC 10 11 12 17 19 ignores invalid colors unlike Kitty"
    } else {
      "xterm color query replies preserve BEL or ST request termination"
    }
    if $ruling.adjudication.proof.symbol != $expected_test {
      error make {msg: $"wrong dynamic-color proof linked to ($id)"}
    }
  }
  let palette_id = ($reference + ".osc.palette")
  let palette = (protocol decision $palette_id)
  if ($palette.disposition != adjudicated
      or $palette.adjudication.winner.owner != xterm
      or $palette.adjudication.loser.owner != $reference
      or $palette.adjudication.proof.symbol != "xterm color query replies preserve BEL or ST request termination") {
    error make {msg: $"indexed OSC 4 request-final mismatch not proven for ($palette_id)"}
  }
}
let color_rulings = (protocol query --text "BEL-terminated color query")
if ($color_rulings | where disposition == adjudicated | length) < 5 {
  error make {msg: "indexed color reply policy is not query-searchable"}
}

for id in [iterm2.osc.palette_reset kitty.osc.palette_reset] {
  let palette_ruling = (protocol decision $id)
  if ($palette_ruling.disposition != adjudicated
      or $palette_ruling.adjudication.kind != wire_collision
      or $palette_ruling.adjudication.winner.owner != xterm
      or ($palette_ruling.adjudication.reason | str trim | is-empty)) {
    error make {msg: $"missing or invalid OSC104 origin arbitration on ($id)"}
  }
}
let whitespace_case = (protocol query --text "whitespace-only reset")
if "kitty.osc.palette_reset" not-in ($whitespace_case | get id) {
  error make {msg: "Kitty whitespace-only loser is not index-queryable"}
}
let junk_case = (protocol query --text "numeric-prefix junk")
if "iterm2.osc.palette_reset" not-in ($junk_case | get id) {
  error make {msg: "iTerm2 trailing-junk loser is not index-queryable"}
}
let search_rulings = (protocol query --text XTQMODKEYS)
if "libvterm.csi.decsgr" not-in ($search_rulings | get id) {
  error make {msg: "adjudicated winner is not query-searchable"}
}
let losing_owner = (protocol query --text "DEC printers")
if "libvterm.csi.decsgr" not-in ($losing_owner | get id) {
  error make {msg: "adjudicated losing protocol owner is not query-searchable"}
}
let malformed_policy = ($catalogue | update collision_policy.implementation_preference [ghostty xterm iterm2 kitty])
require-rule (protocol collision diagnostics $malformed_policy) collision_policy

let target = ($catalogue.references.libvterm.groups.on_csi.records | get "libvterm.csi.decsgr")
let altered = ($target | update howl.adjudication.winner.behavior "")
let broken_index = ($catalogue | update references.libvterm.groups.on_csi.records
  ($catalogue.references.libvterm.groups.on_csi.records | update "libvterm.csi.decsgr" $altered))
require-rule (protocol collision diagnostics $broken_index) collision_shape

let dropped = ($target | reject howl.adjudication)
let lost_ruling = ($catalogue | update references.libvterm.groups.on_csi.records
  ($catalogue.references.libvterm.groups.on_csi.records | update "libvterm.csi.decsgr" $dropped))
require-rule (protocol collision diagnostics $lost_ruling) collision_missing

let wrong_proof = ($target | update howl.adjudication.proof.symbol "a nonexistent test")
let invalid_proof = ($catalogue | update references.libvterm.groups.on_csi.records
  ($catalogue.references.libvterm.groups.on_csi.records | update "libvterm.csi.decsgr" $wrong_proof))
require-rule (protocol collision diagnostics $invalid_proof) collision_proof

let bad_total = ($inventory | update total_records ($inventory.total_records + 1))
require-rule (protocol inventory diagnostics $catalogue $bad_total) inventory_total

let bad_pin = ($catalogue | update references.windows_terminal.revision "not-the-pinned-commit")
require-rule (protocol inventory diagnostics $bad_pin $inventory) reference_pin

let wrong_delta_baseline = ($inventory | update references.kitty_delta.base_revision "not-the-baseline")
require-rule (protocol inventory diagnostics $catalogue $wrong_delta_baseline) delta_baseline
let wrong_delta_scope = ($catalogue | update references.kitty_delta.kind snapshot)
require-rule (protocol inventory diagnostics $wrong_delta_scope $inventory) reference_scope
let wrong_delta_pin = ($catalogue | update references.kitty_delta.revision "moving-head")
require-rule (protocol inventory diagnostics $wrong_delta_pin $inventory) reference_pin

let incomplete_roster = ($inventory | update references.ghostty.group_ids {})
require-rule (protocol inventory diagnostics $catalogue $incomplete_roster) branch_roster_scope

let original_query = ($catalogue.references.windows_terminal.groups.osc52_clipboard.records
  | get "windows_terminal.osc52.query_ignored")
let substituted = ($catalogue.references.windows_terminal.groups.osc52_clipboard.records
  | reject "windows_terminal.osc52.query_ignored"
  | insert "windows_terminal.osc52.impostor" $original_query)
let wrong_ids = ($catalogue | update references.windows_terminal.groups.osc52_clipboard.records $substituted)
require-rule (protocol inventory diagnostics $wrong_ids $inventory) branch_roster

let bad_count = ($inventory | update references.windows_terminal.groups.osc52_clipboard 3)
require-rule (protocol inventory diagnostics $catalogue $bad_count) reference_count
require-rule (protocol inventory diagnostics $catalogue $bad_count) inventory_total

let fewer = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | reject osc9_progress))
require-rule (protocol inventory diagnostics $fewer $inventory) group_inventory

let too_many = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | insert unexpected $catalogue.references.windows_terminal.groups.osc9_progress))
require-rule (protocol inventory diagnostics $too_many $inventory) group_inventory

let seed_group = {
  source: "terminal/adapter/adaptDispatch.cpp"
  line: 3558
  census: {semantic_branches: 2}
  recognition: implemented
  records: {
    "fixture.first": {raw: "OSC fixture;1", effect: "synthetic branch", howl: {support: unassessed}}
    "fixture.second": {raw: "OSC fixture;2", effect: "synthetic branch", howl: {support: unassessed}}
  }
}
let approved_cat = ($catalogue | update references.windows_terminal.groups
  ($catalogue.references.windows_terminal.groups | insert accepted_future $seed_group))
let expanded_ref = ($inventory.references.windows_terminal
  | update total_records 6
  | update groups ($inventory.references.windows_terminal.groups | insert accepted_future 2)
  | update group_ids ($inventory.references.windows_terminal.group_ids | insert accepted_future ["fixture.first" "fixture.second"]))
let approved_inventory = ($inventory
  | update references.windows_terminal $expanded_ref
  | update total_groups ($inventory.total_groups + 1)
  | update total_records ($inventory.total_records + 2))
let approved = (protocol inventory diagnostics $approved_cat $approved_inventory)
if ($approved | length) != 0 {
  error make {msg: $"correctly approved future group failed: ($approved | to json -r)"}
}

let incomplete = ($approved_cat | update references.windows_terminal.groups.accepted_future.records
  ($approved_cat.references.windows_terminal.groups.accepted_future.records | reject "fixture.second"))
require-rule (protocol inventory diagnostics $incomplete $approved_inventory) branch_inventory

print "Protocol inventory: accepted/rejected subtree fixtures passed"
