#!/usr/bin/env python3
"""Validate this three-skill bundle, optionally checking local source evidence.

No network requests are made. Structural/source checks do not establish faithful
paraphrase, semantic equivalence, automatic discovery, or live agent behavior.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
import zipfile
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

try:
    import yaml
except ImportError:
    yaml = None


SKILLS = ("how-to-read-a-book", "research-reading", "github-project-learning")
REMOVED_IDS = {"G32", "G33", "G34", "G51", "G52", "G53", "G54"}
ALLOWED_FIELDS = {"name", "description", "license", "allowed-tools", "metadata"}
RULE_ID = re.compile(r"^[FAGS]\d+$")
RULE_HEADING = re.compile(r"^#{1,6}\s+([FAGS]\d+)\b", re.M)


def normalized(value: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", value)).replace("\u00ad", "")


class TextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def prose(text: str) -> str:
    """Omit fenced and inline code when discovering executable document links."""
    lines, fence, size = [], None, 0
    for line in text.splitlines():
        match = re.match(r"^[ \t]*(?:[-+*]\s+|\d+[.)]\s+)?(`{3,}|~{3,})(.*)$", line)
        if match:
            marker, tail = match.groups()
            if fence is None:
                fence, size = marker[0], len(marker)
            elif marker[0] == fence and len(marker) >= size and not tail.strip():
                fence = None
            lines.append("")
        elif fence is None:
            lines.append(line)
        else:
            lines.append("")
    return re.sub(r"(`+).*?\1", "", "\n".join(lines))


def markdown_destinations(text: str):
    """Inline and reference-style links, including angle-wrapped destinations."""
    text = prose(text)
    definitions = {}
    definition_lines = set()
    for match in re.finditer(r"^ {0,3}\[([^\]\n]+)\]:\s*(<[^>\n]+>|\S+)", text, re.M):
        definitions[" ".join(match[1].casefold().split())] = match[2].strip("<>")
        definition_lines.add(match.start())
    # A small balanced scanner keeps parentheses in file names intact.
    skip_until = 0
    for match in re.finditer(r"\[([^\]\n]*)\]", text):
        if match.start() < skip_until:
            continue
        label, end = match[1], match.end()
        line_start = text.rfind("\n", 0, match.start()) + 1
        if line_start in definition_lines:
            continue
        if end < len(text) and text[end] == "(":
            cursor = end + 1
            while cursor < len(text) and text[cursor].isspace():
                cursor += 1
            if cursor < len(text) and text[cursor] == "<":
                close = text.find(">", cursor + 1)
                if close >= 0:
                    yield text[cursor + 1:close]
                    skip_until = close + 1
                continue
            start, depth = cursor, 0
            while cursor < len(text):
                char = text[cursor]
                if char == "\\" and cursor + 1 < len(text):
                    cursor += 2
                    continue
                if char == "(":
                    depth += 1
                elif char == ")":
                    if depth == 0:
                        break
                    depth -= 1
                elif char.isspace() and depth == 0:
                    break
                cursor += 1
            if cursor > start:
                yield re.sub(r"\\([() ])", r"\1", text[start:cursor])
                skip_until = cursor + 1
        else:
            if end < len(text) and text[end] == "[":
                close = text.find("]", end + 1)
                if close < 0:
                    continue
                label = text[end + 1:close] or label
                skip_until = close + 1
            key = " ".join(label.casefold().split())
            if key in definitions:
                yield definitions[key]


class Validator:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.roots = {name: (self.root if name == SKILLS[0] else self.root.parent / name).resolve()
                      for name in SKILLS}
        self.errors = []
        self.texts = {}
        self.graph = defaultdict(set)
        self.calls = defaultdict(set)
        self.body_lines = {}
        self.records = []
        self.evidence_items = []
        self.metadata = {}
        self.route_count = 0
        self.bundle_version = None
        self.expected_rule_count = None

    def error(self, message):
        if message not in self.errors:
            self.errors.append(message)

    def module(self, path: Path):
        for name, root in self.roots.items():
            if path.is_relative_to(root):
                return name
        return None

    def label(self, path: Path):
        module = self.module(path)
        return f"{module}/{path.relative_to(self.roots[module]).as_posix()}" if module else str(path)

    def read(self, path: Path):
        try:
            return path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as exc:
            self.error(f"Cannot read {self.label(path)}: {type(exc).__name__}: {getattr(exc, 'strerror', None) or 'invalid text encoding'}")
            return None

    def json_file(self, path: Path):
        text = self.read(path)
        if text is None:
            return None
        try:
            return json.loads(text)
        except (ValueError, TypeError) as exc:
            self.error(f"Invalid JSON in {self.label(path)}: {exc}")
            return None

    def load_yaml(self, text, label):
        if yaml is None:
            self.error("Missing dependency: PyYAML (import yaml)")
            return None
        try:
            value = yaml.safe_load(text)
            if not isinstance(value, dict):
                self.error(f"Expected YAML mapping: {label}")
                return None
            return value
        except yaml.YAMLError as exc:
            self.error(f"Invalid YAML in {label}: {exc}")
            return None

    def call_node(self, path):
        owner = self.module(path)
        if owner is None:
            return False
        rel = path.relative_to(self.roots[owner])
        return rel == Path("SKILL.md") or (path.suffix.lower() == ".md" and rel.parts[0] == "workflows")

    def destination(self, source, raw):
        if not isinstance(raw, str) or not raw.strip():
            self.error(f"Empty/non-string link destination in {self.label(source)}")
            return None
        raw = raw.strip()
        parts = urlsplit(raw)
        if parts.scheme and parts.scheme.lower() not in ("file",):
            if len(parts.scheme) == 1:  # Windows drive paths are not external URLs.
                self.error(f"Absolute local link forbidden: {self.label(source)} -> {raw}")
            return None
        if parts.scheme == "file" or raw.startswith(("/", "\\")):
            self.error(f"Absolute local link forbidden: {self.label(source)} -> {raw}")
            return None
        dest = unquote(parts.path)
        if not dest:  # Same-file fragments have no additional file dependency.
            return None
        target = (source.parent / dest).resolve()
        if self.module(target) is None:
            self.error(f"Link leaves the three-skill bundle: {self.label(source)} -> {raw}")
            return None
        if not target.is_file():
            self.error(f"Missing linked file: {self.label(source)} -> {self.label(target)}")
            return None
        self.graph[source].add(target)
        if self.call_node(source) and self.call_node(target):
            self.calls[source].add(target)
        if self.call_node(source) and target == self.root / "routing.yaml":
            self.calls[source].add(target)
        return target

    def structure(self):
        bundle = self.json_file(self.root / "bundle.json")
        expected = {"schema_version": 1, "entry_skill": SKILLS[0],
                    "skills": list(SKILLS), "shared_rules_owner": SKILLS[0]}
        if not isinstance(bundle, dict):
            self.error("bundle.json must be an object describing the complete suite")
        else:
            self.bundle_version = bundle.get("version")
            if not isinstance(self.bundle_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", self.bundle_version):
                self.error("bundle.json version must have major.minor.patch form")
            self.expected_rule_count = bundle.get("source_rule_count")
            if type(self.expected_rule_count) is not int or self.expected_rule_count < 1:
                self.error("bundle.json source_rule_count must be a positive integer")
            for key, value in expected.items():
                if bundle.get(key) != value or (key == "schema_version" and type(bundle.get(key)) is not int):
                    self.error(f"Unexpected bundle.json {key}: expected {value!r}")
            removed = bundle.get("removed_rule_ids")
            if not isinstance(removed, list) or any(not isinstance(x, str) for x in removed) or len(removed) != len(REMOVED_IDS) or set(removed) != REMOVED_IDS:
                self.error("bundle.json removed_rule_ids does not match the seven retired rules")
        for name, root in self.roots.items():
            if not root.is_dir():
                self.error(f"Missing required bundle skill directory: {root}")
                continue
            entry = root / "SKILL.md"
            text = self.read(entry)
            if text is not None:
                self.frontmatter(name, entry, text)
            try:
                paths = sorted(root.rglob("*.md"))
            except OSError as exc:
                self.error(f"Cannot enumerate {root}: {exc.strerror}")
                paths = []
            for path in paths:
                resolved = path.resolve()
                if self.module(resolved) != name:
                    self.error(f"Markdown file escapes owning module: {path}")
                    continue
                content = self.read(resolved)
                if content is None:
                    continue
                self.texts[resolved] = content
                self.graph[resolved]
                if re.search(r"\[TODO:|<!-- FILL:", content):
                    self.error(f"Unfinished content: {self.label(resolved)}")
                for dest in markdown_destinations(content):
                    self.destination(resolved, dest)
        self.routing()
        self.reachability()
        self.rule_inventory()
        self.cross_module_cycles()

    def frontmatter(self, name, path, text):
        match = re.match(r"\A---\s*\n(.*?)\n---(?:\n|$)", text, re.S)
        if not match:
            self.error(f"Invalid SKILL.md frontmatter: {self.label(path)}")
            return
        meta = self.load_yaml(match[1], self.label(path))
        lines = len(text[match.end():].splitlines())
        self.body_lines[name] = lines
        if lines > 90:
            self.error(f"Entry body exceeds 90 lines: {name} ({lines})")
        if meta is None:
            return
        extras = set(meta) - ALLOWED_FIELDS
        if extras:
            self.error(f"Unsupported frontmatter fields in {name}: {', '.join(sorted(map(str, extras)))}")
        value = meta.get("name")
        if not isinstance(value, str) or value != name or len(value) > 64 or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", value):
            self.error(f"Invalid/mismatched frontmatter name: {name}")
        desc = meta.get("description")
        if not isinstance(desc, str) or not desc.strip() or len(desc.strip()) > 1024 or "<" in desc or ">" in desc:
            self.error(f"Invalid description in {name}: require nonempty text <=1024 characters without angle brackets")

    def routing(self):
        path = self.root / "routing.yaml"
        text = self.read(path)
        if text is None:
            return
        self.reject_removed(path, text)
        routes = self.load_yaml(text, self.label(path))
        if routes is None:
            return
        if routes.get("always_read") != []:
            self.error("Main routing.yaml always_read must be []")
        rows = routes.get("task_routes")
        if not isinstance(rows, list) or not rows:
            self.error("Main routing.yaml task_routes must be a nonempty list")
            rows = []
        seen = set()
        for row in rows:
            if not isinstance(row, dict):
                self.error("Invalid task_routes item: expected mapping")
                continue
            rid = row.get("id")
            if not isinstance(rid, str) or not rid.strip():
                self.error("Missing/invalid route ID")
            elif rid in seen:
                self.error(f"Duplicate route ID: {rid}")
            else:
                seen.add(rid)
            target = self.destination(path, row.get("workflow"))
            if target is None or not self.call_node(target) or target.name == "SKILL.md":
                self.error(f"Route {rid!r} must target an existing bundle workflow Markdown file")
            else:
                self.calls[path].add(target)
        self.route_count = len(rows)
        genres = routes.get("genres")
        if not isinstance(genres, dict):
            self.error("Main routing.yaml genres must be a mapping")
            return
        for key, row in genres.items():
            target = self.destination(path, row.get("rules") if isinstance(row, dict) else None)
            if target is None or not target.is_relative_to(self.root / "rules") or target.suffix != ".md":
                self.error(f"Genre {key!r} must target an existing shared main/rules Markdown file")

    def reachability(self):
        pending = [root / "SKILL.md" for root in self.roots.values()]
        visited = set()
        while pending:
            node = pending.pop()
            if node in visited:
                continue
            visited.add(node)
            pending.extend(self.graph.get(node, ()))
        for path in self.texts:
            rel = path.relative_to(self.roots[self.module(path)])
            if rel.parts[0] in ("rules", "workflows") and path not in visited:
                self.error(f"Unreachable rule/workflow from bundle entries: {self.label(path)}")

    def reject_removed(self, path, text):
        present = set(re.findall(r"\bG\d+\b", text)) & REMOVED_IDS
        if present:
            self.error(f"Retired rule IDs in active instructions {self.label(path)}: {', '.join(sorted(present))}")

    def rule_inventory(self):
        headings = defaultdict(list)
        for path, text in self.texts.items():
            module = self.module(path)
            rel = path.relative_to(self.roots[module])
            # Historical reviews may discuss a rule under an ID heading.
            # Only active instructions can own or duplicate a source rule.
            if rel != Path("SKILL.md") and rel.parts[0] not in ("rules", "workflows"):
                continue
            self.reject_removed(path, text)
            for rid in RULE_HEADING.findall(prose(text)):
                headings[rid].append(path)
                if module != SKILLS[0] or rel.parts[0] != "rules":
                    self.error(f"Shared rule heading outside main/rules: {rid} in {self.label(path)}")
        records = self.json_file(self.root / "references/evidence.json")
        if not isinstance(records, list):
            self.error("references/evidence.json must be a list")
            records = []
        self.records = records
        if len(records) != self.expected_rule_count:
            self.error(f"Expected {self.expected_rule_count} retained evidence records; found {len(records)}")
        ids = []
        for record in records:
            if not isinstance(record, dict) or not isinstance(record.get("id"), str) or not RULE_ID.fullmatch(record["id"]):
                self.error("Malformed evidence record ID")
                continue
            rid = record["id"]
            ids.append(rid)
            if rid in REMOVED_IDS:
                self.error(f"Retired rule remains in evidence inventory: {rid}")
            owner = record.get("owner")
            owner_path = (self.root / owner).resolve() if isinstance(owner, str) else None
            if owner_path is None or not owner_path.is_relative_to(self.root / "rules") or headings.get(rid) != [owner_path]:
                self.error(f"Rule ownership mismatch: {rid}; evidence owner={owner!r}, headings={[self.label(p) for p in headings.get(rid, [])]}")
            evidence = record.get("evidence")
            if not isinstance(evidence, list) or not evidence:
                self.error(f"Missing source evidence: {rid}")
                continue
            for ev in evidence:
                if not isinstance(ev, dict):
                    self.error(f"Invalid source evidence item: {rid}")
                    continue
                fields = ("paragraph_id", "quote", "epub", "paragraph_sha256")
                if any(not isinstance(ev.get(k), str) or not ev[k].strip() for k in fields):
                    self.error(f"Missing/invalid evidence fields: {rid}")
                    continue
                if len(ev["quote"]) > 100 or not normalized(ev["quote"]):
                    self.error(f"Invalid short quote (must be nonempty and <=100 characters): {rid}/{ev['paragraph_id']}")
                if not re.fullmatch(r"[0-9a-fA-F]{64}", ev["paragraph_sha256"]):
                    self.error(f"Invalid paragraph SHA-256: {rid}/{ev['paragraph_id']}")
                if type(ev.get("pdf_page")) is not int or ev["pdf_page"] < 1:
                    self.error(f"Invalid PDF page: {rid}/{ev['paragraph_id']}")
                    continue
                self.evidence_items.append((rid, ev))
        if len(ids) != len(set(ids)):
            self.error("Duplicate evidence rule IDs")
        if set(headings) != set(ids):
            self.error(f"Headings/evidence differ: headings_only={sorted(set(headings)-set(ids))}, evidence_only={sorted(set(ids)-set(headings))}")
        if len(headings) != self.expected_rule_count:
            self.error(f"Expected {self.expected_rule_count} unique source rule headings; found {len(headings)}")
        meta = self.json_file(self.root / "references/source-metadata.json")
        if not isinstance(meta, dict):
            self.error("references/source-metadata.json must be an object")
        else:
            self.metadata = meta
            for key in ("epub_sha256", "pdf_sha256"):
                if not isinstance(meta.get(key), str) or not re.fullmatch(r"[0-9a-fA-F]{64}", meta[key]):
                    self.error(f"Invalid reviewed source digest: {key}")

    def cross_module_cycles(self):
        """Tarjan SCC on calls only, not on reference/rule navigation links."""
        indices, low, stack, on_stack, counter = {}, {}, [], set(), 0

        def visit(node):
            nonlocal counter
            indices[node] = low[node] = counter
            counter += 1
            stack.append(node)
            on_stack.add(node)
            for target in sorted(self.calls.get(node, ())):
                if target not in indices:
                    visit(target)
                    low[node] = min(low[node], low[target])
                elif target in on_stack:
                    low[node] = min(low[node], indices[target])
            if low[node] == indices[node]:
                component = []
                while True:
                    item = stack.pop()
                    on_stack.remove(item)
                    component.append(item)
                    if item == node:
                        break
                if len({self.module(item) for item in component}) > 1:
                    self.error("Cross-module workflow call cycle: " + ", ".join(sorted(self.label(item) for item in component)))

        nodes = set(self.calls) | {n for edges in self.calls.values() for n in edges}
        for node in sorted(nodes):
            if node not in indices:
                visit(node)

    def corpus(self, path):
        before = len(self.errors)
        checked = 0
        try:
            rows = json.loads(path.read_text(encoding="utf-8-sig"))
            if not isinstance(rows, list):
                raise ValueError("paragraph corpus must be a JSON list")
            corpus = {}
            for row in rows:
                if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not isinstance(row.get("text"), str):
                    raise ValueError("each corpus entry needs string id and text")
                if row["id"] in corpus:
                    raise ValueError(f"duplicate paragraph ID: {row['id']}")
                corpus[row["id"]] = row
            for rid, ev in self.evidence_items:
                checked += 1
                para = corpus.get(ev["paragraph_id"])
                if para is None:
                    self.error(f"Corpus paragraph missing: {rid}/{ev['paragraph_id']}")
                    continue
                if normalized(ev["quote"]) not in normalized(para["text"]):
                    self.error(f"Paragraph quote mismatch: {rid}/{ev['paragraph_id']}")
                digest = hashlib.sha256(para["text"].encode("utf-8")).hexdigest()
                if digest != ev["paragraph_sha256"].lower():
                    self.error(f"Paragraph digest mismatch: {rid}/{ev['paragraph_id']}")
        except (OSError, UnicodeError, ValueError, TypeError) as exc:
            detail = exc.strerror if isinstance(exc, OSError) else str(exc)
            self.error(f"Cannot verify corpus {path.name}: {type(exc).__name__}: {detail}")
        return {"status": "passed" if len(self.errors) == before and checked else "failed", "file": path.name, "checked_quotes": checked}

    def source(self, path):
        before = len(self.errors)
        checked = 0
        kind = path.suffix.lower().lstrip(".")
        try:
            if kind not in ("epub", "pdf"):
                raise ValueError("source must be an EPUB or PDF")
            with path.open("rb") as source_file:
                actual = hashlib.file_digest(source_file, "sha256").hexdigest()
            if actual != str(self.metadata.get(kind + "_sha256", "")).lower():
                self.error(f"Source SHA-256 differs from reviewed edition: {path.name}")
            if kind == "epub":
                cache = {}
                with zipfile.ZipFile(path) as archive:
                    for rid, ev in self.evidence_items:
                        checked += 1
                        name = ev["epub"]
                        try:
                            if name not in cache:
                                parser = TextParser()
                                parser.feed(archive.read(name).decode("utf-8"))
                                cache[name] = normalized("".join(parser.parts))
                            if normalized(ev["quote"]) not in cache[name]:
                                self.error(f"Source quote mismatch: {rid}/{ev['paragraph_id']}")
                        except (KeyError, UnicodeError, ValueError) as exc:
                            self.error(f"Cannot read EPUB member {name!r} for {rid}/{ev['paragraph_id']}: {type(exc).__name__}")
            else:
                try:
                    import pymupdf
                except ImportError:
                    raise ValueError("PDF verification requires PyMuPDF (import pymupdf)") from None
                with pymupdf.open(path) as doc:
                    cache = {}
                    for rid, ev in self.evidence_items:
                        checked += 1
                        start = ev["pdf_page"] - 1
                        if start >= len(doc):
                            self.error(f"PDF page out of range: {rid}/{ev['paragraph_id']} page {start + 1}")
                            continue
                        if start not in cache:
                            # This SHA-pinned edition's reviewed text region omits headers.
                            # Paragraph locators give the first page; paragraphs may span pages.
                            cache[start] = normalized("".join(doc[i].get_text(clip=pymupdf.Rect(0, 0, 420, 570))
                                                              for i in range(start, min(start + 4, len(doc)))))
                        if normalized(ev["quote"]) not in cache[start]:
                            self.error(f"Source quote mismatch: {rid}/{ev['paragraph_id']}")
        except Exception as exc:
            # Library exceptions may contain the input absolute filename: redact it.
            detail = getattr(exc, "strerror", None) or str(exc)
            for spelling in (str(path), str(path.absolute()), str(path.resolve())):
                detail = detail.replace(spelling, path.name)
            self.error(f"Cannot verify source {path.name}: {type(exc).__name__}: {detail}")
        return {"status": "passed" if len(self.errors) == before and checked else "failed", "file": path.name,
                "checked_quotes": checked, "checks": ["reviewed-edition SHA-256", "short quote presence"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="Main how-to-read-a-book directory; sibling skills are resolved from its parent")
    parser.add_argument("--source", type=Path, help="Local original EPUB or reviewed PDF; no upload")
    parser.add_argument("--corpus", type=Path, help="Local paragraph JSON; checks paragraph hashes and quotes independently")
    parser.add_argument("--structure-only", action="store_true", help="Check only bundle structure, explicitly without original-source verification")
    parser.add_argument("--report", type=Path, help="Additionally write the same JSON report to this file")
    args = parser.parse_args()
    if args.structure_only and (args.source is not None or args.corpus is not None):
        parser.error("--structure-only cannot be combined with --source or --corpus")
    if args.report is not None and any(p is not None and args.report.resolve() == p.resolve()
                                      for p in (args.source, args.corpus)):
        parser.error("--report must not overwrite the local source or paragraph corpus")
    validator = Validator(args.root)
    try:
        validator.structure()
    except Exception as exc:
        validator.error(f"Structure validation could not complete: {type(exc).__name__}: {exc}")
    structural_errors = list(validator.errors)
    source_status = {"status": "not_run", "reason": "原文未核验：未提供 --source"}
    corpus_status = {"status": "not_run", "reason": "未提供 --corpus"}
    if args.source is not None:
        source_status = validator.source(args.source)
    if args.corpus is not None:
        corpus_status = validator.corpus(args.corpus)
    no_mode = not args.structure_only and args.source is None and args.corpus is None
    if no_mode:
        validator.error("No validation mode selected; 原文未核验。Use --source, --corpus, or explicitly --structure-only.")
    exit_code = 2 if no_mode else (1 if validator.errors else 0)
    report = {
        "bundle_version": validator.bundle_version, "skills": list(SKILLS),
        "mode": "structure_only" if args.structure_only else ("evidence" if not no_mode else "unspecified"),
        "structure": "passed" if not structural_errors else "failed",
        "rule_count": len(validator.records), "expected_rule_count": validator.expected_rule_count,
        "quote_count": len(validator.evidence_items), "route_count": validator.route_count,
        "workflow_count": sum(1 for p in validator.texts if p.relative_to(validator.roots[validator.module(p)]).parts[0] == "workflows"),
        "entry_body_lines": validator.body_lines,
        "source_evidence": source_status, "paragraph_evidence": corpus_status,
        "semantic_equivalence": "not proved; requires recorded human/agent review",
        "automatic_activation_and_behavior": "not tested by this script",
        "errors": validator.errors, "exit_code": exit_code,
    }
    if args.report is not None:
        try:
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            validator.error(f"Cannot write report {args.report}: {type(exc).__name__}: {getattr(exc, 'strerror', None) or 'encoding error'}")
            report["exit_code"] = exit_code = 2 if no_mode else 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
