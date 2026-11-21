# Howl protocol catalogue queries. Source this file; it never mutates persistent configuration.

const protocol_root = (path self | path dirname)
const catalogue_path = ($protocol_root | path join protocol_coverage.yml)
const inventory_path = ($protocol_root | path join protocol_coverage_inventory.yml)
const evidence_path = ($protocol_root | path join tools protocol_evidence.py)
export const protocol_support = [full partial missing unassessed]
export const protocol_disposition = ["none" active delegated deferred excluded adjudicated]
export const protocol_owner = [howl-vt howl-pty howl-app]
const howl_record_fields = [support disposition owner residual rationale milestone source symbol proof adjudication]
const reference_fields = [revision root groups kind base_reference base_revision scope]
const group_fields = [source line census recognition records bounds symbol conditions]
const record_fields = [raw effect relevance howl conditions recognition bounds source symbol line]
export const protocol_cheatsheet = [
  "protocol                         compact coverage summary"
  "protocol gaps                    active partial/missing/unassessed records"
  "protocol list                    compact filtered human table; shows 25 rows by default"
  "protocol list --limit 50         override the human row bound; --all shows every row"
  "protocol query ...               normalized structured records, including adjudicated decisions"
  "protocol records                 every normalized structured record"
  "protocol decisions               all resolved wire conflicts and their reasons"
  "protocol decision RECORD_ID      one conflict decision with precedence policy"
  "protocol validate                structured diagnostics"
  "protocol validate --fail         fail on diagnostics (build gate)"
  "protocol json                    deterministic normalized JSON"
  "disposition adjudicated marks an impossible same-wire conflict settled by Captain policy"
  "disposition describes the remaining residual obligation, not implemented support"
  "full records normalize to disposition none; incomplete omissions normalize active"
]

def support-complete [] { $protocol_support }
def disposition-complete [] { $protocol_disposition }
def owner-complete [] { $protocol_owner }
def reference-complete [] { open $catalogue_path | get references | columns | sort }
def id-complete [] { protocol records | get id }
def load-catalogue [] { open $catalogue_path }

def normalize-record [reference: string, revision: string, root: string, group_key: string, group: record, record_id: string, record: record] {
  let howl = ($record.howl? | default {})
  let support = ($howl.support? | default unassessed)
  let disposition = ($howl.disposition? | default (if $support == full { "none" } else { "active" }))
  {
    id: $record_id
    reference: $reference
    revision: $revision
    group: $group_key
    raw: ($record.raw? | default "")
    effect: ($record.effect? | default "")
    relevance: ($record.relevance? | default "")
    recognition: ($record.recognition? | default ($group.recognition? | default ""))
    support: $support
    disposition: $disposition
    owner: (if $disposition in [excluded adjudicated] { null } else { $howl.owner? | default howl-vt })
    residual: ($howl.residual? | default ($record.conditions? | default ""))
    rationale: ($howl.rationale? | default "")
    adjudication: ($howl.adjudication? | default null)
    milestone: ($howl.milestone? | default "")
    reference_source: ($record.source? | default ($group.source? | default ""))
    reference_symbol: ($record.symbol? | default ($group.symbol? | default $group_key))
    reference_line: ($record.line? | default ($group.line? | default null))
    source: ($howl.source? | default "")
    symbol: ($howl.symbol? | default "")
    proof: ($howl.proof? | default null)
  }
}

export def "protocol records" [] {
  let catalogue = (open $catalogue_path)
  $catalogue.references
  | transpose reference facts
  | each {|reference|
      $reference.facts.groups
      | transpose group facts
      | each {|group|
          $group.facts.records
          | transpose id record
          | each {|record|
              normalize-record $reference.reference $reference.facts.revision $reference.facts.root $group.group $group.facts $record.id $record.record
            }
        }
      | flatten
    }
  | flatten
  | sort-by reference group id
}

export def "protocol query" [
  --support: string@support-complete
  --disposition: string@disposition-complete
  --owner: string@owner-complete
  --reference: string@reference-complete
  --relevance: string
  --text: string
] {
  protocol records
  | where {|row| $support == null or $row.support == $support }
  | where {|row| $disposition == null or $row.disposition == $disposition }
  | where {|row| $owner == null or $row.owner == $owner }
  | where {|row| $reference == null or $row.reference == $reference }
  | where {|row| $relevance == null or $row.relevance == $relevance }
  | where {|row|
      let decision = ($row.adjudication | default {})
      $text == null or ([
        $row.id $row.raw $row.effect $row.residual $row.rationale
        ($decision.wire? | default "")
        ($decision.reason? | default "")
        ($decision.winner?.protocol? | default "")
        ($decision.winner?.owner? | default "")
        ($decision.winner?.behavior? | default "")
        ($decision.loser?.protocol? | default "")
        ($decision.loser?.owner? | default "")
        ($decision.loser?.behavior? | default "")
        ($decision.current_usage? | default "")
        ($decision.recency? | default "")
      ] | str join " " | str contains -i $text)
    }
}

export def "protocol decisions" [] {
  protocol records
  | where adjudication != null
  | select id reference disposition adjudication
}

export def "protocol decision" [id: string@id-complete] {
  let rows = (protocol query | where id == $id)
  if ($rows | is-empty) { error make {msg: $"unknown protocol record: ($id)"} }
  let row = ($rows | first)
  if $row.adjudication == null {
    error make {msg: $"protocol record has no adjudicated wire collision: ($id)"}
  }
  {
    id: $row.id
    disposition: $row.disposition
    policy: ((load-catalogue).collision_policy)
    adjudication: $row.adjudication
  }
}

export def "protocol gaps" [] {
  protocol query
  | where disposition == active
  | where support in [partial missing unassessed]
}

export def "protocol summary" [] {
  protocol records
  | upsert owner {|row| $row.owner | default "none" }
  | group-by support disposition owner --to-table
  | each {|row| {
      support: $row.support
      disposition: $row.disposition
      owner: $row.owner
      count: ($row.items | length)
    } }
  | sort-by support disposition owner
}

def diagnostic [id: string, rule: string, detail: string] { {id: $id, rule: $rule, detail: $detail} }

export def "protocol inventory diagnostics" [catalogue: record, inventory: record] {
  mut findings = []
  if $inventory.schema != 1 {
    $findings = ($findings | append (diagnostic inventory schema "inventory schema must be 1"))
  }
  let actual_names = ($catalogue.references | columns | sort)
  let expected_names = ($inventory.references | columns | sort)
  if $actual_names != $expected_names {
    $findings = ($findings | append (diagnostic inventory reference_inventory
      $"reference set differs: expected ($expected_names | to json -r), got ($actual_names | to json -r)"))
  }
  let accepted_count = ($inventory.references | transpose reference facts
    | each {|reference| $reference.facts.groups | values | math sum }
    | math sum)
  let accepted_groups = ($inventory.references | transpose reference facts
    | each {|reference| $reference.facts.groups | columns | length }
    | math sum)
  if $accepted_count != $inventory.total_records or $accepted_groups != $inventory.total_groups {
    $findings = ($findings | append (diagnostic inventory inventory_total
      "reviewed group totals disagree with the independent inventory totals"))
  }
  let group_count = ($catalogue.references | transpose reference facts
    | each {|reference| $reference.facts.groups | columns | length }
    | math sum)
  if $group_count != $inventory.total_groups {
    $findings = ($findings | append (diagnostic catalogue group_count
      $"expected ($inventory.total_groups) reviewed groups, found ($group_count)"))
  }
  for reference in ($inventory.references | transpose reference expected) {
    if $reference.reference not-in $actual_names {
      continue
    }
    let actual = ($catalogue.references | get $reference.reference)
    if $actual.revision != $reference.expected.revision or $actual.root != $reference.expected.root {
      $findings = ($findings | append (diagnostic $reference.reference reference_pin
        "reference revision or root differs from the independently reviewed pin"))
    }
    let expected_kind = ($reference.expected.kind? | default snapshot)
    let actual_kind = ($actual.kind? | default snapshot)
    if ($actual_kind != $expected_kind or
        ($actual.base_reference? | default "") != ($reference.expected.base_reference? | default "") or
        ($actual.base_revision? | default "") != ($reference.expected.base_revision? | default "") or
        ($actual.scope? | default "") != ($reference.expected.scope? | default "")) {
      $findings = ($findings | append (diagnostic $reference.reference reference_scope
        "reference snapshot/delta scope differs from the reviewed inventory"))
    }
    if $expected_kind == delta {
      let base_name = ($reference.expected.base_reference? | default "")
      if $base_name not-in $expected_names {
        $findings = ($findings | append (diagnostic $reference.reference delta_baseline
          "delta baseline reference is not part of the reviewed inventory"))
      } else {
        let base_revision = ($inventory.references | get $base_name | get revision)
        if $base_revision != ($reference.expected.base_revision? | default "") {
          $findings = ($findings | append (diagnostic $reference.reference delta_baseline
            "delta must cite the reviewed immutable baseline revision"))
        }
      }
    }
    let current_groups = ($actual.groups | columns | sort)
    let approved_groups = ($reference.expected.groups | columns | sort)
    if $current_groups != $approved_groups {
      $findings = ($findings | append (diagnostic $reference.reference group_inventory
        "group names differ from the reviewed dispatch subtree inventory"))
    }
    let accepted_ids = ($reference.expected.group_ids? | default {})
    let accepted_id_groups = ($accepted_ids | columns | sort)
    if $expected_kind != snapshot and $accepted_id_groups != $approved_groups {
      $findings = ($findings | append (diagnostic $reference.reference branch_roster_scope
        "reviewed group ID roster must cover each scoped group"))
    }
    let branch_count = ($actual.groups | transpose name group
      | each {|group| $group.group.records | columns | length } | math sum)
    if ($branch_count != $reference.expected.total_records or
        ($reference.expected.groups | values | math sum) != $reference.expected.total_records) {
      $findings = ($findings | append (diagnostic $reference.reference reference_count
        "record count differs from the independently reviewed reference total"))
    }
    for group in ($reference.expected.groups | transpose name count) {
      if $group.name in $current_groups {
        let actual_branch_count = ($actual.groups | get $group.name | get records | columns | length)
        if $actual_branch_count != $group.count {
          $findings = ($findings | append (diagnostic $"($reference.reference).($group.name)" branch_inventory
            $"expected ($group.count) reviewed branches, found ($actual_branch_count)"))
        }
        if $group.name in $accepted_id_groups {
          let actual_ids = ($actual.groups | get $group.name | get records | columns | sort)
          let expected_ids = ($accepted_ids | get $group.name | sort)
          if $actual_ids != $expected_ids {
            $findings = ($findings | append (diagnostic $"($reference.reference).($group.name)" branch_roster
              "branch identities differ from the reviewed reference group"))
          }
        }
      }
    }
  }
  $findings
}

# Schema-4 wire-collision decisions are first-class index data, not free text.
# This diagnostic is pure so corrupted policy/rulings can be exercised in fixtures.
export def "protocol collision diagnostics" [catalogue: record] {
  mut findings = []
  let policy = ($catalogue.collision_policy? | default {})
  let required_order = [protocol_origin exact_effects current_usage implementation_preference protocol_recency]
  if (($policy.default? | default "") != "implement_full"
      or ($policy.criteria? | default []) != $required_order
      or ($policy.implementation_preference? | default []) != [kitty xterm iterm2 ghostty]
      or ($policy.unresolved? | default "") != "refer_to_captain"
      or ($policy.meaning? | default "" | str trim | is-empty)) {
    $findings = ($findings | append (diagnostic catalogue collision_policy
      "collision policy must prioritize origin, exact effects, current use, implementation order, newer protocol and Captain escalation"))
  }
  for reference in ($catalogue.references | transpose name facts) {
    for group in ($reference.facts.groups | transpose name facts) {
      for record in ($group.facts.records | transpose id value) {
        let howl = ($record.value.howl? | default {})
        let disposition = ($howl.disposition? | default "")
        let adjudication = ($howl.adjudication? | default null)
        if $adjudication == null {
          if $disposition == adjudicated {
            $findings = ($findings | append (diagnostic $record.id collision_missing
              "adjudicated disposition requires a complete structured conflict decision"))
          }
          continue
        }
        if $disposition != adjudicated or ($howl.support? | default "") == full {
          $findings = ($findings | append (diagnostic $record.id collision_disposition
            "adjudicated wire conflict must remain incomplete against its pinned losing reference"))
        }
        let winner = ($adjudication.winner? | default {})
        let loser = ($adjudication.loser? | default {})
        let evidence = ($adjudication.proof? | default {})
        let fields = [
          ($adjudication.kind? | default "") ($adjudication.wire? | default "")
          ($winner.owner? | default "") ($winner.protocol? | default "")
          ($winner.behavior? | default "") ($winner.evidence? | default "")
          ($loser.owner? | default "") ($loser.protocol? | default "")
          ($loser.behavior? | default "") ($loser.evidence? | default "")
          ($adjudication.current_usage? | default "") ($adjudication.recency? | default "")
          ($adjudication.reason? | default "")
          ($evidence.path? | default "") ($evidence.symbol? | default "")
        ]
        if (($adjudication.kind? | default "") != wire_collision
            or ($fields | any {|field| ($field | str trim | is-empty)})
            or ($winner.protocol? | default "") == ($loser.protocol? | default "")
            or ($winner.owner? | default "") == ($loser.owner? | default "")) {
          $findings = ($findings | append (diagnostic $record.id collision_shape
            "wire collision requires distinct owners, incompatible effects, source evidence, usage, recency, reason and named proof"))
        }
        let path = ($evidence.path? | default "")
        let symbol = ($evidence.symbol? | default "")
        if $path != "" and $symbol != "" {
          let proof_path = ($protocol_root | path join $path)
          let test_decl = (['test "' $symbol '"'] | str join "")
          if not ($proof_path | path exists) or not ((open --raw $proof_path) | str contains $test_decl) {
            $findings = ($findings | append (diagnostic $record.id collision_proof
              "adjudicated collision must point to a real named Zig regression test"))
          }
        }
      }
    }
  }
  $findings
}

export def "protocol validate" [--fail] {
  let catalogue = (load-catalogue)
  let inventory = (open $inventory_path)
  mut findings = []
  if $catalogue.schema != 4 {
    $findings = ($findings | append (diagnostic catalogue schema "schema must be 4"))
  }
  if ($catalogue.howl_schema.support != $protocol_support
      or $catalogue.howl_schema.disposition != $protocol_disposition
      or $catalogue.howl_schema.owner != $protocol_owner
      or $catalogue.howl_schema.defaults.full_disposition != "none"
      or $catalogue.howl_schema.defaults.incomplete_disposition != active
      or $catalogue.howl_schema.defaults.owner != howl-vt) {
    $findings = ($findings | append (diagnostic catalogue schema_values
      "catalogue enums and query completions differ"))
  }
  $findings = ($findings | append (protocol inventory diagnostics $catalogue $inventory))
  $findings = ($findings | append (protocol collision diagnostics $catalogue))
  for reference in ($catalogue.references | transpose reference facts) {
    for field in ($reference.facts | columns | where {|field| $field not-in $reference_fields }) {
      $findings = ($findings | append (diagnostic $reference.reference unknown_reference_field $"unknown reference field: ($field)"))
    }
    for group in ($reference.facts.groups | transpose group facts) {
      for field in ($group.facts | columns | where {|field| $field not-in $group_fields }) {
        $findings = ($findings | append (diagnostic $"($reference.reference).($group.group)" unknown_group_field $"unknown group field: ($field)"))
      }
      if ($group.facts.records | columns | length) != $group.facts.census.semantic_branches {
        $findings = ($findings | append (diagnostic $"($reference.reference).($group.group)" census
          $"expected ($group.facts.census.semantic_branches) records, found ($group.facts.records | columns | length)"))
      }
      for record in ($group.facts.records | transpose id value) {
        let howl = ($record.value.howl? | default {})
        for field in ($record.value | columns | where {|field| $field not-in $record_fields }) {
          $findings = ($findings | append (diagnostic $record.id unknown_record_field $"unknown record field: ($field)"))
        }
        for field in ($howl | columns | where {|field| $field not-in $howl_record_fields }) {
          $findings = ($findings | append (diagnostic $record.id unknown_howl_field
            $"unknown howl field: ($field)"))
        }
        if ($howl.support? | default null) == null {
          $findings = ($findings | append (diagnostic $record.id explicit_support "howl.support is required"))
        }
        if ($howl.disposition? | default active) == excluded and ($howl.owner? | default null) != null {
          $findings = ($findings | append (diagnostic $record.id excluded_owner "excluded records omit owner"))
        }
      }
    }
  }
  let records = (protocol records)
  if ($records | length) != $inventory.total_records {
    $findings = ($findings | append (diagnostic catalogue record_count
      $"expected ($inventory.total_records) reviewed records, found ($records | length)"))
  }
  let duplicate_ids = ($records | group-by id --to-table | where ($it.items | length) != 1 | get id)
  for id in $duplicate_ids { $findings = ($findings | append (diagnostic $id duplicate_id "id must be unique")) }
  let record_ids = ($records | get id)
  let overlaps = ($catalogue.selective_overlaps? | default [])
  let duplicate_overlaps = ($overlaps | group-by id --to-table | where ($it.items | length) != 1 | get id)
  for id in $duplicate_overlaps {
    $findings = ($findings | append (diagnostic $id duplicate_overlap "overlap id must be unique"))
  }
  for overlap in $overlaps {
    if (($overlap.raw? | default "" | str trim | is-empty)
        or ($overlap.conflict? | default "" | str trim | is-empty)) {
      $findings = ($findings | append (diagnostic $overlap.id overlap_shape
        "overlap requires nonempty raw and conflict"))
    }
    for reference in ($overlap.references? | default []) {
      if $reference not-in $record_ids {
        $findings = ($findings | append (diagnostic $overlap.id overlap_reference
          $"unknown record: ($reference)"))
      }
    }
  }
  for row in $records {
    if $row.support not-in $protocol_support {
      $findings = ($findings | append (diagnostic $row.id support $"unknown support: ($row.support)"))
    }
    if $row.disposition not-in $protocol_disposition {
      $findings = ($findings | append (diagnostic $row.id disposition $"unknown disposition: ($row.disposition)"))
    }
    if $row.owner != null and $row.owner not-in $protocol_owner {
      $findings = ($findings | append (diagnostic $row.id owner $"unknown owner: ($row.owner)"))
    }
    if $row.support == full and ($row.source == "" or $row.symbol == "" or $row.proof == null) {
      $findings = ($findings | append (diagnostic $row.id full_evidence "full requires source, symbol, and proof"))
    }
    if $row.support == full and $row.disposition != "none" {
      $findings = ($findings | append (diagnostic $row.id full_disposition
        "full support has no residual obligation and requires disposition none"))
    }
    if $row.support != full and $row.disposition == "none" {
      $findings = ($findings | append (diagnostic $row.id incomplete_disposition
        "incomplete support has a residual obligation and cannot use disposition none"))
    }
    if $row.proof != null and (($row.proof.path? | default "" | str trim | is-empty)
        or ((($row.proof.symbol? | default ($row.proof.test? | default "")) | str trim | is-empty))) {
      $findings = ($findings | append (diagnostic $row.id proof_shape "proof requires path and symbol or test"))
    }
    if $row.support == partial and ($row.residual | str trim | is-empty) {
      $findings = ($findings | append (diagnostic $row.id partial_residual "partial requires an exact residual"))
    }
    if $row.disposition == delegated and ($row.owner == howl-vt or $row.proof == null) {
      $findings = ($findings | append (diagnostic $row.id delegated_handoff
        "delegated requires a non-VT owner and proof of the VT handoff"))
    }
    if $row.support == missing and $row.disposition == delegated {
      $findings = ($findings | append (diagnostic $row.id missing_delegated
        "missing behavior has no completed handoff to delegate"))
    }
    if $row.disposition == deferred and (($row.milestone | str trim | is-empty) or $row.owner == null) {
      $findings = ($findings | append (diagnostic $row.id deferred_milestone
        "deferred requires a real owner and milestone"))
    }
    if $row.disposition == excluded and $row.owner != null {
      $findings = ($findings | append (diagnostic $row.id excluded_owner "excluded records have no owner"))
    }
    if $row.disposition == excluded and ($row.rationale | str trim | is-empty) {
      $findings = ($findings | append (diagnostic $row.id excluded_rationale
        "excluded residuals require a permanent-scope rationale"))
    }
    if ($row.support == partial and $row.disposition == excluded
        and ($row.proof == null or ($row.residual | str trim | is-empty))) {
      $findings = ($findings | append (diagnostic $row.id partial_excluded
        "partial excluded records require implementation proof and an exact excluded residual"))
    }
    if ($row.reference_source | str trim | is-empty) or ($row.reference_symbol | str trim | is-empty) {
      $findings = ($findings | append (diagnostic $row.id reference_evidence
        "reference source and symbol are required"))
    }
    if $row.source != "" and not ($protocol_root | path join $row.source | path exists) {
      $findings = ($findings | append (diagnostic $row.id source_path $"missing ($row.source)"))
    }
    if $row.proof != null and not ($protocol_root | path join ($row.proof.path? | default "") | path exists) {
      $findings = ($findings | append (diagnostic $row.id proof_path $"missing ($row.proof.path?)"))
    }
    if ($findings | length) >= 256 { break }
  }
  # One bounded pass over each cited Zig file; unlike path-only checks this
  # verifies named test declarations, real function owners and test-root reachability.
  let declarations = ($records | to json | python3 -B $evidence_path $protocol_root | from json)
  $findings = ($findings | append $declarations)
  let result = if ($findings | length) >= 256 {
    $findings | first 255 | append (diagnostic catalogue diagnostic_limit "validation stopped at 256 diagnostics")
  } else { $findings }
  if $fail and not ($result | is-empty) {
    $result | to json --indent 2 | print --stderr
    error make {msg: $"protocol catalogue has ($result | length) diagnostics"}
  }
  $result
}

export def "protocol json" [] { protocol records | to json }

def compact [] {
  $in | select id reference support disposition owner | table --theme compact
}

export def protocol [] { protocol summary | table --theme compact }
export def "protocol list" [
  --support: string@support-complete
  --disposition: string@disposition-complete
  --owner: string@owner-complete
  --reference: string@reference-complete
  --text: string
  --limit: int = 25
  --all
] {
  if $limit < 1 { error make {msg: "protocol list --limit must be positive"} }
  let rows = (protocol query --support $support --disposition $disposition --owner $owner
    --reference $reference --text $text)
  let total = ($rows | length)
  let shown = if $all { $total } else { [$limit $total] | math min }
  let facts = ([{shown: $shown, total: $total, truncated: ($shown < $total)}]
    | table --theme compact)
  let body = if $shown == 0 {
    "no matching records"
  } else {
    $rows | first $shown | compact
  }
  [$facts $body] | str join (char nl)
}
export def "protocol show" [id: string@id-complete] {
  let rows = (protocol query | where id == $id)
  if ($rows | is-empty) {
    "record not found"
  } else {
    $rows | first | transpose field value | table --theme compact --expand
  }
}
export def "protocol help" [] {
  let rows = ($protocol_cheatsheet | each {|line| {command: $line} })
  $rows | table --theme compact
}

export alias pc = protocol
export alias pcg = protocol gaps
export alias pcq = protocol query
