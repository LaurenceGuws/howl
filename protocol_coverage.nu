# Howl protocol catalogue queries. Source this file; it never mutates persistent configuration.

const protocol_root = (path self | path dirname)
const catalogue_path = ($protocol_root | path join protocol_coverage.yml)
export const protocol_support = [full partial missing unassessed]
export const protocol_disposition = ["none" active delegated deferred excluded]
export const protocol_owner = [howl-vt howl-host howl-control howl-render howl-pty]
export const protocol_cheatsheet = [
  "protocol                         compact coverage summary"
  "protocol gaps                    active partial/missing/unassessed records"
  "protocol list                    compact filtered human table; shows 25 rows by default"
  "protocol list --limit 50         override the human row bound; --all shows every row"
  "protocol query ...               normalized structured records"
  "protocol records                 every normalized structured record"
  "protocol validate                structured diagnostics"
  "protocol validate --fail         fail on diagnostics (build gate)"
  "protocol json                    deterministic normalized JSON"
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
    owner: (if $disposition == excluded { null } else { $howl.owner? | default howl-vt })
    residual: ($howl.residual? | default ($record.conditions? | default ""))
    rationale: ($howl.rationale? | default "")
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
      $text == null or ([$row.id $row.raw $row.effect $row.residual] | str join " " | str contains -i $text)
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

export def "protocol validate" [--fail] {
  let catalogue = (load-catalogue)
  mut findings = []
  if $catalogue.schema != 3 {
    $findings = ($findings | append (diagnostic catalogue schema "schema must be 3"))
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
  let group_count = ($catalogue.references | transpose reference facts
    | each {|reference| $reference.facts.groups | columns | length }
    | math sum)
  if $group_count != 34 {
    $findings = ($findings | append (diagnostic catalogue group_count
      $"expected 34 groups, found ($group_count)"))
  }
  for reference in ($catalogue.references | transpose reference facts) {
    for group in ($reference.facts.groups | transpose group facts) {
      if ($group.facts.records | columns | length) != $group.facts.census.semantic_branches {
        $findings = ($findings | append (diagnostic $"($reference.reference).($group.group)" census
          $"expected ($group.facts.census.semantic_branches) records, found ($group.facts.records | columns | length)"))
      }
      for record in ($group.facts.records | transpose id value) {
        if ($record.value.howl.support? | default null) == null {
          $findings = ($findings | append (diagnostic $record.id explicit_support "howl.support is required"))
        }
        if ($record.value.howl.disposition? | default active) == excluded and ($record.value.howl.owner? | default null) != null {
          $findings = ($findings | append (diagnostic $record.id excluded_owner "excluded records omit owner"))
        }
      }
    }
  }
  let records = (protocol records)
  if ($records | length) != 662 {
    $findings = ($findings | append (diagnostic catalogue record_count
      $"expected 662 records, found ($records | length)"))
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
