#!/usr/bin/env python3

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

from quality_owner_resolver import (
    DEFAULT_MANIFEST,
    DEFAULT_REGISTRY,
    RegistryError,
    load_manifest,
    load_registry,
    resolve_quality_context,
)


SCHEMA_VERSION = 1
SUCCESS_STATUSES = {"QUALITY_OK", "QUALITY_NOT_APPLICABLE"}
EMPTY_CHANGES = {
    "committed": [],
    "staged": [],
    "unstaged": [],
    "untracked": [],
    "changed_paths": [],
}


class AuditError(RuntimeError):
    pass


def git(repo, *arguments, check=True):
    completed = subprocess.run(
        ["git", "-C", repo, *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and completed.returncode != 0:
        message = completed.stderr.decode("utf-8", "replace").strip()
        raise AuditError("git %s failed in %s: %s" % (arguments[0], repo, message))
    return completed


def decode_paths(raw):
    return sorted(
        {
            item.decode("utf-8", "surrogateescape")
            for item in raw.split(b"\0")
            if item
        }
    )


def decode_diff_paths(raw):
    tokens = [item for item in raw.split(b"\0") if item]
    paths = set()
    index = 0
    while index < len(tokens):
        status = tokens[index].decode("ascii", "strict")
        index += 1
        if not status or status[0] not in "ACDMRTUXB":
            raise AuditError("git diff emitted an invalid name-status record")
        path_count = 2 if status[0] in "RC" else 1
        if index + path_count > len(tokens):
            raise AuditError("git diff emitted a truncated name-status record")
        for raw_path in tokens[index:index + path_count]:
            paths.add(raw_path.decode("utf-8", "surrogateescape"))
        index += path_count
    return sorted(paths)


def rev_exists(repo, ref):
    return git(repo, "rev-parse", "--verify", "--quiet", "%s^{commit}" % ref, check=False).returncode == 0


def commit_for_ref(repo, ref):
    return git(repo, "rev-parse", "--verify", "%s^{commit}" % ref).stdout.decode().strip()


def tree_for_commit(repo, commit):
    return git(repo, "show", "-s", "--format=%T", commit).stdout.decode().strip()


def commit_if_ref_exists(repo, ref):
    completed = git(
        repo,
        "rev-parse",
        "--verify",
        "--quiet",
        "%s^{commit}" % ref,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.decode().strip()


def canonical_base_commit(repo, base_ref):
    if re.fullmatch(r"[0-9a-fA-F]{40}", base_ref):
        object_type = git(repo, "cat-file", "-t", base_ref, check=False)
        if (
            object_type.returncode != 0
            or object_type.stdout.decode("ascii", "strict").strip() != "commit"
        ):
            raise AuditError("base commit SHA is missing or is not a commit")
        return commit_for_ref(repo, base_ref)

    if base_ref.startswith("refs/"):
        commit = commit_if_ref_exists(repo, base_ref)
        if commit is None:
            raise AuditError("base ref %s is missing" % base_ref)
        return commit

    local_ref = "refs/heads/%s" % base_ref
    remote_ref = "refs/remotes/origin/%s" % base_ref
    local_commit = commit_if_ref_exists(repo, local_ref)
    remote_commit = commit_if_ref_exists(repo, remote_ref)
    if local_commit and remote_commit and local_commit != remote_commit:
        raise AuditError(
            "base ref %s local and origin refs differ" % base_ref
        )
    commit = local_commit or remote_commit
    if commit is None:
        raise AuditError("base ref %s is missing" % base_ref)
    return commit


def worktrees(repo):
    output = git(repo, "worktree", "list", "--porcelain", "-z").stdout
    records = []
    current = {}
    for field in output.split(b"\0"):
        if not field:
            if current:
                records.append(current)
                current = {}
            continue
        raw_key, separator, raw_value = field.partition(b" ")
        key = raw_key.decode("ascii", "strict")
        value = os.fsdecode(raw_value) if key == "worktree" else raw_value.decode("utf-8", "surrogateescape")
        if not separator:
            value = ""
        current[key] = value
    if current:
        records.append(current)
    return records


def ref_relation(repo, left_commit, right_commit):
    left_contains_right = git(
        repo,
        "merge-base",
        "--is-ancestor",
        right_commit,
        left_commit,
        check=False,
    ).returncode == 0
    right_contains_left = git(
        repo,
        "merge-base",
        "--is-ancestor",
        left_commit,
        right_commit,
        check=False,
    ).returncode == 0
    if left_contains_right:
        return "left-ahead"
    if right_contains_left:
        return "right-ahead"
    return "diverged"


def candidate_for(repo, topic_branch):
    wanted = "refs/heads/%s" % topic_branch
    remote_ref = "refs/remotes/origin/%s" % topic_branch
    for record in worktrees(repo):
        if record.get("branch") == wanted:
            worktree_path = os.path.realpath(record["worktree"])
            if rev_exists(repo, remote_ref):
                worktree_commit = commit_for_ref(worktree_path, "HEAD")
                remote_commit = commit_for_ref(repo, remote_ref)
                if worktree_commit != remote_commit:
                    relation = ref_relation(repo, worktree_commit, remote_commit)
                    if relation == "right-ahead":
                        raise AuditError(
                            "topic branch %s origin ahead of matching worktree"
                            % topic_branch
                        )
                    if relation == "diverged":
                        raise AuditError(
                            "topic branch %s matching worktree diverged from origin"
                            % topic_branch
                        )
            return {
                "kind": "worktree",
                "path": worktree_path,
                "ref": topic_branch,
                "git_ref": "HEAD",
            }
    local_exists = rev_exists(repo, wanted)
    remote_exists = rev_exists(repo, remote_ref)
    if local_exists and remote_exists:
        local_commit = commit_for_ref(repo, wanted)
        remote_commit = commit_for_ref(repo, remote_ref)
        if local_commit != remote_commit:
            relation = ref_relation(repo, local_commit, remote_commit)
            if relation == "left-ahead":
                relation = "local ahead of origin"
            elif relation == "right-ahead":
                relation = "origin ahead of local"
            else:
                relation = "diverged"
            raise AuditError(
                "topic branch %s local and origin refs differ: %s"
                % (topic_branch, relation)
            )
    if local_exists:
        return {
            "kind": "branch",
            "path": os.path.realpath(repo),
            "ref": topic_branch,
            "git_ref": wanted,
        }
    if remote_exists:
        return {
            "kind": "branch",
            "path": os.path.realpath(repo),
            "ref": "origin/%s" % topic_branch,
            "git_ref": remote_ref,
        }
    return {
        "kind": "missing",
        "path": os.path.realpath(repo),
        "ref": topic_branch,
        "git_ref": None,
    }


def public_candidate(candidate):
    return {
        "kind": candidate["kind"],
        "path": candidate["path"],
        "ref": candidate["ref"],
    }


def collect_changes(candidate, base_ref):
    if candidate["kind"] == "missing":
        return dict(EMPTY_CHANGES)
    repo = candidate["path"]
    target_ref = canonical_candidate_ref(candidate)
    committed = decode_diff_paths(
        git(
            repo,
            "diff",
            "--name-status",
            "-z",
            "--find-renames",
            "%s..%s" % (base_ref, target_ref),
        ).stdout
    )
    staged = []
    unstaged = []
    untracked = []
    if candidate["kind"] == "worktree":
        staged = decode_diff_paths(
            git(repo, "diff", "--cached", "--name-status", "-z", "--find-renames").stdout
        )
        unstaged = decode_diff_paths(
            git(repo, "diff", "--name-status", "-z", "--find-renames").stdout
        )
        untracked = decode_paths(
            git(repo, "ls-files", "--others", "--exclude-standard", "-z").stdout
        )
    return {
        "committed": committed,
        "staged": staged,
        "unstaged": unstaged,
        "untracked": untracked,
        "changed_paths": sorted(set(committed + staged + unstaged + untracked)),
    }


def find_product_module(registry, product_id, module_id):
    for product in registry.get("products") or []:
        if product.get("id") != product_id:
            continue
        for module in product.get("modules") or []:
            if module.get("id") == module_id:
                return product, module
    raise RegistryError("module not found %s/%s" % (product_id, module_id))


def layer_directories(manifest):
    directories = {layer.get("id"): layer.get("dir") for layer in manifest.get("layers") or []}
    if not directories.get("impl") or not directories.get("quality"):
        raise RegistryError("manifest must define impl and quality directories")
    return directories


def module_repo_path(registry, manifest, identity, layer):
    product_id, separator, module_id = identity.partition("/")
    if not separator:
        raise RegistryError("invalid module identity %s" % identity)
    product, _ = find_product_module(registry, product_id, module_id)
    product_root = os.path.expanduser(str((product.get("repo") or {}).get("path") or ""))
    if not product_root:
        raise RegistryError("%s has no product repo path" % product_id)
    directories = layer_directories(manifest)
    if not directories.get(layer):
        raise RegistryError("manifest must define %s directory" % layer)
    return os.path.join(product_root, directories[layer], module_id)


def markdown_cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def clean_cell(cell):
    return cell.strip().strip("`").strip()


def is_separator_row(cells):
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells)


def markdown_tables(text):
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        if not lines[index].lstrip().startswith("|"):
            index += 1
            continue
        table = []
        while index < len(lines) and lines[index].lstrip().startswith("|"):
            table.append(markdown_cells(lines[index]))
            index += 1
        if len(table) >= 2 and is_separator_row(table[1]):
            yield table[0], table[2:]


def extract_patterns(cell):
    code_spans = re.findall(r"`([^`]+)`", cell)
    values = code_spans or re.split(r"、|<br\s*/?>", clean_cell(cell))
    return [value.strip() for value in values if value.strip()]


def parse_plan_text(text):
    baselines = {}
    patterns = []
    for header, rows in markdown_tables(text):
        cleaned_header = [clean_cell(cell) for cell in header]
        if {"上游 repo", "commit", "tree"}.issubset(cleaned_header):
            repo_index = cleaned_header.index("上游 repo")
            commit_index = cleaned_header.index("commit")
            tree_index = cleaned_header.index("tree")
            for row in rows:
                if len(row) <= max(repo_index, commit_index, tree_index):
                    continue
                upstream_repo = clean_cell(row[repo_index])
                if upstream_repo in baselines:
                    raise AuditError(
                        "duplicate baseline row for upstream repo: %s" % upstream_repo
                    )
                baselines[upstream_repo] = {
                    "commit": clean_cell(row[commit_index]),
                    "tree": clean_cell(row[tree_index]),
                }
            continue
        if len(cleaned_header) in (2, 3) and "路徑" in cleaned_header[0] and "區碼" in cleaned_header[1]:
            for row in rows:
                if len(row) >= 2:
                    patterns.extend(extract_patterns(row[0]))
    return baselines, sorted(set(patterns))


def read_candidate_file(candidate, relative_path):
    git_relative_path = relative_path.replace("\\", "/")
    if candidate["kind"] == "worktree":
        with open(os.path.join(candidate["path"], *git_relative_path.split("/")), encoding="utf-8") as handle:
            return handle.read()
    if candidate["kind"] == "branch":
        completed = git(
            candidate["path"],
            "show",
            "%s:%s" % (canonical_candidate_ref(candidate), git_relative_path),
        )
        return completed.stdout.decode("utf-8", "replace")
    raise AuditError("candidate file cannot be read from a missing candidate")


def canonical_candidate_ref(candidate):
    git_ref = candidate.get("git_ref")
    if not git_ref:
        raise AuditError("candidate has no canonical git ref")
    return git_ref


def candidate_git_location(candidate):
    return candidate["path"], canonical_candidate_ref(candidate)


def base_is_ancestor(candidate, base_ref):
    candidate_repo, candidate_ref = candidate_git_location(candidate)
    return git(
        candidate_repo,
        "merge-base",
        "--is-ancestor",
        base_ref,
        candidate_ref,
        check=False,
    ).returncode == 0


def path_matches(pattern, path):
    if pattern.endswith("/"):
        return path.startswith(pattern)
    if any(character in pattern for character in "*?["):
        return fnmatch.fnmatchcase(path, pattern)
    return path == pattern


def validate_baseline(source_repo, candidate, baseline):
    if not baseline:
        return False, "missing baseline row"
    commit = baseline.get("commit", "")
    declared_tree = baseline.get("tree", "")
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(r"[0-9a-f]{40}", declared_tree):
        return False, "baseline commit and tree must be lowercase 40-character hashes"
    object_type = git(source_repo, "cat-file", "-t", commit, check=False)
    if object_type.returncode != 0:
        return False, "baseline commit is not available in source repo"
    if object_type.stdout.decode("ascii", "strict").strip() != "commit":
        return False, "baseline commit hash is not a native commit object"
    actual_tree = git(source_repo, "show", "-s", "--format=%T", commit).stdout.decode().strip()
    if actual_tree != declared_tree:
        return False, "baseline tree does not match baseline commit"
    if candidate["kind"] == "missing":
        return True, ""
    candidate_repo, candidate_ref = candidate_git_location(candidate)
    if git(candidate_repo, "merge-base", "--is-ancestor", commit, candidate_ref, check=False).returncode != 0:
        return False, "baseline commit is not an ancestor of source candidate"
    return True, ""


def empty_result(product, module, topic_branch):
    missing = {"kind": "missing", "path": "", "ref": topic_branch}
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "QUALITY_OWNER_INVALID",
        "product": product,
        "source_module": module,
        "owner": None,
        "spec_candidate": dict(missing),
        "impl_candidate": dict(missing),
        "quality_candidate": dict(missing),
        "spec_changes": dict(EMPTY_CHANGES),
        "impl_changes": dict(EMPTY_CHANGES),
        "quality_changes": dict(EMPTY_CHANGES),
        "changed_paths": [],
        "diagnostics": [],
    }


def audit(registry_path, manifest_path, product_id, module_id, topic_branch, base_ref):
    result = empty_result(product_id, module_id, topic_branch)
    try:
        registry = load_registry(registry_path)
        manifest = load_manifest(manifest_path)
        owner_context = resolve_quality_context(registry, product_id, module_id, manifest)
        owner = owner_context["owner"]
        result["owner"] = owner
    except Exception as error:
        result["diagnostics"].append(str(error) or error.__class__.__name__)
        return result

    if owner == "none":
        result["status"] = "QUALITY_NOT_APPLICABLE"
        return result

    try:
        source_identity = "%s/%s" % (product_id, module_id)
        _, source_module = find_product_module(registry, product_id, module_id)
        source_repo = module_repo_path(registry, manifest, source_identity, "impl")
        quality_repo = owner_context["quality_path"]
        has_spec_repo = "spec" in (source_module.get("repos") or {})
        spec_repo = (
            module_repo_path(registry, manifest, source_identity, "spec")
            if has_spec_repo
            else None
        )
        if not os.path.isdir(os.path.join(source_repo, ".git")) and not os.path.isfile(os.path.join(source_repo, ".git")):
            raise RegistryError("source impl repo is missing %s" % source_repo)
        if not os.path.isdir(os.path.join(quality_repo, ".git")) and not os.path.isfile(os.path.join(quality_repo, ".git")):
            raise RegistryError("quality owner repo is missing %s" % quality_repo)
        if spec_repo and not os.path.isdir(os.path.join(spec_repo, ".git")) and not os.path.isfile(os.path.join(spec_repo, ".git")):
            raise RegistryError("source spec repo is missing %s" % spec_repo)
        spec_candidate = (
            candidate_for(spec_repo, topic_branch)
            if spec_repo
            else {
                "kind": "missing",
                "path": "",
                "ref": topic_branch,
                "git_ref": None,
            }
        )
        impl_candidate = candidate_for(source_repo, topic_branch)
        quality_candidate = candidate_for(quality_repo, topic_branch)
        result["spec_candidate"] = public_candidate(spec_candidate)
        result["impl_candidate"] = public_candidate(impl_candidate)
        result["quality_candidate"] = public_candidate(quality_candidate)
    except (AuditError, OSError, RegistryError) as error:
        result["status"] = "QUALITY_BASELINE_INVALID"
        result["diagnostics"].append(str(error))
        return result

    if impl_candidate["kind"] == "missing":
        result["status"] = "QUALITY_REFRESH_REQUIRED"
        result["diagnostics"].append("source topic branch is missing")
        return result

    try:
        try:
            source_base_commit = canonical_base_commit(source_repo, base_ref)
        except AuditError as error:
            result["status"] = "QUALITY_BASELINE_INVALID"
            result["diagnostics"].append("source %s" % error)
            return result
        if not base_is_ancestor(impl_candidate, source_base_commit):
            result["status"] = "QUALITY_BASELINE_INVALID"
            result["diagnostics"].append("source base ref is not an ancestor of source candidate")
            return result
        impl_changes = collect_changes(impl_candidate, source_base_commit)
        result["impl_changes"] = impl_changes
        result["changed_paths"] = list(impl_changes["changed_paths"])

        if quality_candidate["kind"] == "missing":
            result["status"] = "QUALITY_REFRESH_REQUIRED"
            result["diagnostics"].append("quality topic branch is missing")
            return result
        try:
            quality_base_commit = canonical_base_commit(quality_repo, base_ref)
        except AuditError as error:
            result["status"] = "QUALITY_BASELINE_INVALID"
            result["diagnostics"].append("quality %s" % error)
            return result
        if not base_is_ancestor(quality_candidate, quality_base_commit):
            result["status"] = "QUALITY_BASELINE_INVALID"
            result["diagnostics"].append("quality base ref is not an ancestor of quality candidate")
            return result
        result["quality_changes"] = collect_changes(
            quality_candidate,
            quality_base_commit,
        )

        if spec_repo:
            try:
                spec_base_commit = canonical_base_commit(spec_repo, base_ref)
            except AuditError as error:
                result["status"] = "QUALITY_BASELINE_INVALID"
                result["diagnostics"].append("spec %s" % error)
                return result
            if spec_candidate["kind"] != "missing":
                if not base_is_ancestor(spec_candidate, spec_base_commit):
                    result["status"] = "QUALITY_BASELINE_INVALID"
                    result["diagnostics"].append(
                        "spec base ref is not an ancestor of spec candidate"
                    )
                    return result
                result["spec_changes"] = collect_changes(
                    spec_candidate,
                    spec_base_commit,
                )

        plan_text = read_candidate_file(
            quality_candidate,
            "no2_regression_plan/no0_index.md",
        )
        baselines, patterns = parse_plan_text(plan_text)
        source_key = "%s/%s" % (layer_directories(manifest)["impl"], module_id)
        baseline = baselines.get(source_key)
        valid, diagnostic = validate_baseline(source_repo, impl_candidate, baseline)
        if not valid:
            result["status"] = "QUALITY_BASELINE_INVALID"
            result["diagnostics"].append(diagnostic)
            return result

        if spec_repo:
            spec_key = "%s/%s" % (layer_directories(manifest)["spec"], module_id)
            spec_baseline = baselines.get(spec_key)
            valid, diagnostic = validate_baseline(
                spec_repo,
                spec_candidate,
                spec_baseline,
            )
            if not valid:
                result["status"] = "QUALITY_BASELINE_INVALID"
                result["diagnostics"].append("spec %s" % diagnostic)
                return result

            if spec_candidate["kind"] == "missing":
                spec_base_tree = tree_for_commit(spec_repo, spec_base_commit)
                if (
                    spec_baseline["commit"] != spec_base_commit
                    or spec_baseline["tree"] != spec_base_tree
                ):
                    result["status"] = "QUALITY_BASELINE_INVALID"
                    result["diagnostics"].append(
                        "spec baseline does not match explicit base ref"
                    )
                    return result
            else:
                spec_changes = result["spec_changes"]
                if spec_changes["changed_paths"]:
                    result["status"] = "QUALITY_REFRESH_REQUIRED"
                    result["diagnostics"].append(
                        "source spec topic contains changes that Stage 1 cannot map"
                    )
                    return result
                spec_candidate_repo, spec_candidate_ref = candidate_git_location(
                    spec_candidate
                )
                spec_candidate_commit = commit_for_ref(
                    spec_candidate_repo,
                    spec_candidate_ref,
                )
                spec_candidate_tree = tree_for_commit(
                    spec_candidate_repo,
                    spec_candidate_commit,
                )
                if (
                    spec_baseline["commit"] != spec_candidate_commit
                    or spec_baseline["tree"] != spec_candidate_tree
                ):
                    result["status"] = "QUALITY_REFRESH_REQUIRED"
                    result["diagnostics"].append(
                        "quality baseline does not cover the complete spec candidate"
                    )
                    return result

        gaps = [
            path
            for path in impl_changes["changed_paths"]
            if not any(path_matches(pattern, path) for pattern in patterns)
        ]
        if gaps:
            result["status"] = "QUALITY_MAPPING_GAP"
            result["diagnostics"].extend("unmapped source path: %s" % path for path in gaps)
            return result

        if len(owner_context["source_modules"]) > 1:
            result["status"] = "QUALITY_MAPPING_GAP"
            result["diagnostics"].append(
                "shared quality owner requires repo-aware mapping before coverage can be confirmed"
            )
            return result

        candidate_repo, candidate_ref = candidate_git_location(impl_candidate)
        candidate_commit = commit_for_ref(candidate_repo, candidate_ref)
        candidate_tree = tree_for_commit(candidate_repo, candidate_commit)
        has_dirty_source = any(
            impl_changes[key] for key in ("staged", "unstaged", "untracked")
        )
        if baseline["commit"] != candidate_commit or baseline["tree"] != candidate_tree or has_dirty_source:
            result["status"] = "QUALITY_REFRESH_REQUIRED"
            result["diagnostics"].append("quality baseline does not cover the complete source candidate")
            return result

        result["status"] = "QUALITY_OK"
        return result
    except (AuditError, OSError, ValueError) as error:
        result["status"] = "QUALITY_BASELINE_INVALID"
        result["diagnostics"].append(str(error))
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", default=DEFAULT_REGISTRY)
    parser.add_argument("--layer-manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--product", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--topic-branch", required=True)
    parser.add_argument("--base-ref", required=True)
    arguments = parser.parse_args()
    result = audit(
        arguments.registry,
        arguments.layer_manifest,
        arguments.product,
        arguments.module,
        arguments.topic_branch,
        arguments.base_ref,
    )
    json.dump(result, sys.stdout, ensure_ascii=True, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if result["status"] in SUCCESS_STATUSES else 1


if __name__ == "__main__":
    sys.exit(main())
