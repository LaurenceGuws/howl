#!/usr/bin/env python3
"""Validate the static VT specification's structural links, not its semantics."""
from pathlib import Path
import re
import sys

import yaml


class UniqueKeys(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            require(key not in result, f"duplicate YAML key {key!r}")
            result[key] = self.construct_object(value_node, deep=deep)
        return result


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value):
    return isinstance(value, str) and bool(value.strip())


CLAUSE_FIELDS = set("""id section level wire dispatch mode_context rule
source_locator source_note relations details evidence disposition
disposition_reason test_locations""".split())
REQUIRED = set("id section level wire rule".split())
RELATIONS = {"extends", "reaffirms", "equivalent", "alias", "conflicts", "related"}
ID = re.compile(r"[a-z][a-z0-9_-]*")
DISPATCH = re.compile(
    r"BYTE [0-9A-F]{2}|ESC (?:0x[0-9A-F]{2}|(?:(?:SP|[!-/]) )*[0-~])"
    r"|(?:CSI|DCS) (?:[<=>?] )?(?:[0-9]+ )?(?:(?:SP|[!-/]) )*[@-~]"
    r"|OSC (?:[0-9]+|\*)|(?:APC|PM) [!-~]+"
)


def validate(data, root):
    require(data["schema"] == 2, "expected protocol schema 2")
    require(data["kind"] == "terminal-protocol-specifications", "wrong index kind")
    clauses = {}
    for source_id, source in data["specifications"].items():
        require(ID.fullmatch(source_id), f"invalid source ID {source_id}")
        for field in ("title", "author", "authority", "revision", "url", "scope"):
            require(text(source.get(field)), f"{source_id}: missing {field}")
        if "snapshot_sha256" in source:
            require(re.fullmatch(r"[0-9a-f]{64}", source["snapshot_sha256"]),
                    f"{source_id}: invalid snapshot hash")
        require(isinstance(source["clauses"], list) and source["clauses"],
                f"{source_id}: no clauses")
        for clause in source["clauses"]:
            cid = source_id + "." + clause["id"]
            require(ID.fullmatch(clause["id"]) and cid not in clauses,
                    f"invalid or duplicate clause {cid}")
            require(REQUIRED <= clause.keys() <= CLAUSE_FIELDS,
                    f"{cid}: unknown or missing common fields")
            require(all(text(clause[k]) for k in REQUIRED), f"{cid}: empty source definition")
            clauses[cid] = clause

    files = {}
    test_links = 0

    def tests(locations):
        nonlocal test_links
        for loc in locations:
            path = (root / loc["file"]).resolve()
            require(path.is_relative_to(root.resolve()), "test path outside repository")
            if path not in files:
                files[path] = path.read_text()
            pattern = r'^\s*test\s+"' + re.escape(loc["test"]) + r'"\s*\{'
            require(len(re.findall(pattern, files[path], re.M)) == 1,
                    f"missing or ambiguous test: {loc['file']}: {loc['test']}")
            test_links += 1

    relationships = 0
    keyed = 0
    for cid, c in clauses.items():
        if "dispatch" in c:
            keys = c["dispatch"]
            require(isinstance(keys, list) and keys and len(keys) == len(set(keys)),
                    f"{cid}: invalid dispatch list")
            require(all(DISPATCH.fullmatch(k) for k in keys), f"{cid}: invalid dispatch key")
            keyed += 1
        for rel in c.get("relations", []):
            require(rel.get("kind") in RELATIONS, f"{cid}: unknown relation")
            require(set(rel) <= {"kind", "role", "clause", "note"} and
                    ("clause" in rel) != ("note" in rel), f"{cid}: invalid relation shape")
            require("role" not in rel or
                    (rel["kind"] == "related" and text(rel["role"])), f"{cid}: invalid role")
            if "clause" in rel:
                require(rel["clause"] in clauses, f"{cid}: dangling relation {rel['clause']}")
            else:
                require(text(rel["note"]), f"{cid}: empty relationship note")
            relationships += 1
        for field in ("details", "evidence"):
            if field in c:
                require(isinstance(c[field], dict), f"{cid}: invalid {field}")
        tests(c.get("test_locations", []))
    clause_test_links = test_links
    decisions = {}
    active = {}
    for d in data["reconciliation"]:
        did = d["id"]
        require(ID.fullmatch(did) and did not in decisions, f"duplicate decision {did}")
        applies(d, clauses)
        require("superseded_in_part" not in d, f"{did}: use forward supersedes edges")
        selected = d.get("selects", {})
        for key, field in selected.items():
            require(text(key) and field in d["accepted_interpretation"],
                    f"{did}: missing selected interpretation {field}")
            active.setdefault(key, set()).add(did)
        for edge in d.get("supersedes", []):
            earlier = edge["decision"]
            require(earlier in decisions, f"{did}: supersession must refer to an earlier decision")
            require(text(edge["scope"]), f"{did}: missing semantic supersession scope")
            keys = edge["selection_keys"]
            require(isinstance(keys, list) and keys and len(keys) == len(set(keys)),
                    f"{did}: missing or duplicate supersession selection keys")
            for key in keys:
                require(key in selected and key in decisions[earlier].get("selects", {}),
                        f"{did}: supersession of undeclared facet {key}")
                active[key].discard(earlier)
        if "implementation_assessment" in d:
            a = d["implementation_assessment"]
            require(a["status"] in {"MISSING", "PARTIAL", "FULL"},
                    f"{did}: unknown assessment status")
            tests(a.get("tests", []))
        decisions[did] = d
    for key, owners in active.items():
        require(len(owners) == 1, f"{key}: unresolved selection precedence {sorted(owners)}")
    pending_ids = set()
    for d in data["pending_reconciliation"]:
        did = d["id"]
        require(ID.fullmatch(did) and did not in decisions and did not in pending_ids,
                f"duplicate pending ID {did}")
        applies(d, clauses)
        require(d["decision"] is None and "selects" not in d and
                "implementation_assessment" not in d, f"{did}: pending conflict has selection")
        for ref in d["original_author_sources"]:
            require(ref["clause"] in d["applies_to"]["clauses"], f"{did}: missing source in scope")
        pending_ids.add(did)
    require(all("pending_reconciliation" not in c
                for c in data["discovery_catalogues"].values()), "catalogue-owned pending conflict")
    return {
        "sources": len(data["specifications"]), "clauses": len(clauses),
        "keyed_clauses": keyed, "relations": relationships, "decisions": len(decisions),
        "pending": len(pending_ids), "clause_test_links": clause_test_links,
        "assessment_test_links": test_links - clause_test_links,
        "effective_selections": {k: next(iter(v)) for k, v in sorted(active.items())},
    }


def applies(d, clauses):
    scope = d["applies_to"]
    refs = scope["clauses"]
    require(set(scope) == {"clauses", "scope"} and text(scope["scope"]),
            f"{d['id']}: missing applicability scope")
    require(isinstance(refs, list) and refs and len(refs) == len(set(refs)) and
            all(ref in clauses for ref in refs), f"{d['id']}: invalid applicability references")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    try:
        data = yaml.load((root / "protocol_specs.yml").read_text(), Loader=UniqueKeys)
        print(yaml.safe_dump(validate(data, root), sort_keys=False), end="")
    except (ValueError, KeyError, TypeError, OSError, yaml.YAMLError) as error:
        print(f"protocol specification: {error}", file=sys.stderr)
        sys.exit(1)
