# Interactive views over Howl's reference protocol census.
#
# Load from any directory with:
#   source /path/to/howl-vt/protocol_coverage.nu

let protocol_coverage_file = ($env.FILE_PWD | path join reference_sequences.yml)

def protocol-records [] {
    open $protocol_coverage_file
    | get references
    | transpose reference spec
    | each {|ref|
        $ref.spec.groups
        | each {|group|
            let group_name = (
                $group
                | get -o symbol
                | default ($group | get -o source | default unknown)
            )

            $group.records
            | each {|record| {
                reference: $ref.reference
                group: $group_name
                recognition: ($group | get -o recognition | default unknown)
                id: $record.id
                raw: $record.raw
                effect: $record.effect
                relevance: ($record | get -o relevance | default unknown)
                status: ($record | get -o howl.status | default unassessed)
                source: ($record | get -o howl.source)
                proof: ($record | get -o howl.proof)
            }}
        }
        | flatten
    }
    | flatten
}

def complete-reference [] {
    protocol-records | get reference | uniq | sort
}

def complete-status [] {
    protocol-records
    | get status
    | uniq
    | sort
    | each {|status| {
        value: (if $status == 'false' { "'false'" } else { $status })
        description: $"Howl status: ($status)"
    }}
}

def complete-relevance [] {
    protocol-records | get relevance | uniq | sort
}

def complete-group [] {
    protocol-records | get group | uniq | sort
}

def complete-record-id [] {
    protocol-records | get id | sort
}

# Show the protocol coverage help page.
def "protocol coverage" [] {
    protocol coverage help
}

# Show setup, commands, examples, and interactive completion hints.
def "protocol coverage help" [] {
    print $'(ansi attr_bold)Howl protocol coverage(ansi reset)

Explore the protocol census in reference_sequences.yml.

(ansi attr_bold)Commands(ansi reset)
  protocol coverage summary [reference]    Counts and coverage percentages
  protocol coverage list [flags]           Filter and search census records
  protocol coverage show <id>              Show one record and its proof
  protocol coverage gaps [reference]       Rank incomplete protocol families
  protocol coverage unproven               Find implementations without proof
  protocol coverage help                   Show this page

(ansi attr_bold)Examples(ansi reset)
  protocol coverage summary
  protocol coverage summary kitty
  protocol coverage list --reference kitty --status partial
  protocol coverage list --status "false"
  protocol coverage list --search clipboard
  protocol coverage show libvterm.c0.bel
  protocol coverage gaps iterm2

(ansi attr_bold)Interactive use(ansi reset)
  Press Tab after a reference, status, relevance, group, or record ID.
  Add --help to any subcommand for its complete flags and arguments.'
}

# Count full, partial, missing, and unassessed records by reference.
def "protocol coverage summary" [
    reference?: string@complete-reference # Restrict the summary to one reference.
] {
    let records = if $reference == null {
        protocol-records
    } else {
        protocol-records | where reference == $reference
    }

    $records
    | group-by reference
    | transpose reference rows
    | each {|entry|
        let total = $entry.rows | length
        let full = $entry.rows | where status == 'full' | length
        let partial = $entry.rows | where status == 'partial' | length
        let missing = $entry.rows | where status == 'false' | length
        let unassessed = $entry.rows | where status == 'unassessed' | length

        {
            reference: $entry.reference
            total: $total
            full: $full
            partial: $partial
            missing: $missing
            unassessed: $unassessed
            full_percent: ($full * 100 / $total | math round --precision 1)
            touched_percent: (($full + $partial) * 100 / $total | math round --precision 1)
        }
    }
    | sort-by reference
}

# List census records, with optional exact filters and a text search.
def "protocol coverage list" [
    --reference (-r): string@complete-reference
    --status (-s): string@complete-status
    --relevance: string@complete-relevance
    --group (-g): string@complete-group
    --search (-q): string # Case-insensitive search over ID, raw sequence, and effect.
] {
    protocol-records
    | if $reference != null { where reference == $reference } else { }
    | if $status != null { where status == $status } else { }
    | if $relevance != null { where relevance == $relevance } else { }
    | if $group != null { where group == $group } else { }
    | if $search != null {
        where (
            ($it.id | str contains --ignore-case $search)
            or ($it.raw | str contains --ignore-case $search)
            or ($it.effect | str contains --ignore-case $search)
        )
    } else { }
    | select reference group id raw effect relevance status source
}

# Show one record, including its proof metadata.
def "protocol coverage show" [
    id: string@complete-record-id
] {
    protocol-records | where id == $id | first
}

# Rank protocol families by their remaining coverage gaps.
def "protocol coverage gaps" [
    reference?: string@complete-reference
] {
    protocol-records
    | if $reference != null { where reference == $reference } else { }
    | each {|row|
        $row | insert family $"($row.reference)/($row.group)"
    }
    | group-by family
    | transpose family rows
    | each {|entry| {
        family: $entry.family
        total: ($entry.rows | length)
        full: ($entry.rows | where status == 'full' | length)
        partial: ($entry.rows | where status == 'partial' | length)
        missing: ($entry.rows | where status == 'false' | length)
        unassessed: ($entry.rows | where status == 'unassessed' | length)
    }}
    | where missing > 0 or partial > 0 or unassessed > 0
    | sort-by missing partial --reverse
}

# Find implemented records that do not name executable proof.
def "protocol coverage unproven" [] {
    protocol-records
    | where status in ['full' 'partial']
    | where proof == null
    | select reference group id status source
}
