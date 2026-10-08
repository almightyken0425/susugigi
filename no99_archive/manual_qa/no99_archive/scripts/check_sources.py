#!/usr/bin/env python3
"""Read-only checks for the step-two source inventory; never executes product tests."""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import re
import subprocess
import sys

def sha(value):
    return hashlib.sha256(value).hexdigest()

def load_yaml(path):
    # Psych is available in the current authoring environment. Reject duplicate
    # mappings before safe loading, because silent overwrites hide source gaps.
    script = r'''
require 'yaml'
require 'json'
text = STDIN.read
ast = Psych.parse_stream(text)
raise 'exactly one document required' unless ast.children.length == 1
walk = lambda do |node|
  if node.is_a?(Psych::Nodes::Alias)
    raise 'aliases are not allowed'
  end
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map do |pair|
      raise 'mapping keys must be scalar strings' unless pair[0].is_a?(Psych::Nodes::Scalar)
      pair[0].value
    end
    raise 'duplicate mapping key' unless keys.uniq.length == keys.length
  end
  (node.children || []).each { |child| walk.call(child) } if node.respond_to?(:children)
end
walk.call(ast)
STDOUT.write(JSON.generate(Psych.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)))
'''
    result = subprocess.run(['ruby', '-e', script], input=path.read_text(), text=True, capture_output=True)
    if result.returncode:
        raise ValueError(f'{path.name}: invalid YAML: {result.stderr.strip()}')
    return json.loads(result.stdout)

def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)

def check(index, cases, contract, root, overrides):
    errors = []
    def require(ok, message):
        if not ok:
            errors.append(message)
    require(index['schema_version'] == contract['schema_version'] == '1.0', 'schema version mismatch')
    repos = {r['id']: r for r in index['repositories']}
    ids = set()
    source_ids = {s['id'] for s in index['sources']}
    node_ids = {n['id'] for s in index['sources'] for n in s['nodes']}
    open_gaps = {g['id'] for g in index['gaps'] if g['status'] == 'open'}
    contexts = {c['id'] for s in index['sources'] for c in s['contexts']}
    def unique(value):
        require(value not in ids, f'duplicate ID: {value}')
        ids.add(value)
    def shape(record, kind):
        require(set(record) == set(contract['source_record_fields'][kind]), f'wrong fields: {kind}: {record.get("id", "index")}')
    shape(index, 'index')
    for repo in index['repositories']:
        shape(repo, 'repository')
    paths = collections.defaultdict(set)
    blobs = {}
    for s in index['sources']:
        shape(s, 'source')
        unique(s['id'])
        repo = repos[s['repository']]
        checkout = Path(overrides.get(repo['id'], repo['checkout_hint'])).expanduser()
        path = Path(s['path'])
        require(not path.is_absolute() and '..' not in path.parts, f'nonportable source path: {path}')
        require(s['path'] not in paths[repo['id']], f'duplicate source path: {path}')
        paths[repo['id']].add(s['path'])
        raw = git(checkout, 'show', repo['commit']+':'+s['path'])
        blobs[s['id']] = raw
        require(sha(raw) == s['sha256'], f'source hash mismatch: {s["id"]}')
        require(git(checkout, 'rev-parse', repo['commit']+':'+s['path']).decode().strip() == s['blob'], f'blob mismatch: {s["id"]}')
        lines = raw.decode().splitlines()
        require(len(lines) == s['line_count'], f'line count mismatch: {s["id"]}')
        own_nodes = {n['id'] for n in s['nodes']}
        own_contexts = {c['id'] for c in s['contexts']}
        covered = set()
        for context in s['contexts']:
            shape(context, 'context')
            unique(context['id'])
            a,b = context['line_start'],context['line_end']
            require('\n'.join(lines[a-1:b]) == context['quote'], f'context quote mismatch: {context["id"]}')
        for node in s['nodes']:
            shape(node, 'node')
            unique(node['id'])
            a,b = node['line_start'],node['line_end']
            require(1 <= a <= b <= len(lines), f'bad span: {node["id"]}')
            expected = '\n'.join(lines[a-1:b])
            # Whole-file basis quotes retain the original trailing newline.
            require(node['quote'].rstrip('\n') == expected, f'node quote mismatch: {node["id"]}')
            covered.update(range(a,b+1))
            require(node['context_ref'] is None or node['context_ref'] in own_contexts, f'missing context: {node["id"]}')
            require(node['disposition'] in contract['source_dispositions'], f'bad disposition: {node["id"]}')
            require(node['kind'] in contract['node_kinds'], f'bad kind: {node["id"]}')
            require(bool(node['reason']), f'missing disposition reason: {node["id"]}')
            require(all(g in open_gaps for g in node['gap_refs']), f'dangling or resolved node gap: {node["id"]}')
            require((node['disposition']=='requirement') == bool(node['claims']), f'claims/disposition mismatch: {node["id"]}')
            for parent in node['ancestors']:
                require(parent['node_ref'] in own_nodes, f'foreign/missing ancestor: {node["id"]}')
            for claim in node['claims']:
                shape(claim, 'claim')
                unique(claim['id'])
                require(bool(claim['text']), f'empty claim: {claim["id"]}')
                require(claim['status'] in contract['requirement_states'], f'bad claim status: {claim["id"]}')
                require(all(g in open_gaps for g in claim['gap_refs']), f'dangling or resolved gap: {claim["id"]}')
                require((claim['status']=='source_gap') == bool(claim['gap_refs']), f'gap status mismatch: {claim["id"]}')
        for i,line in enumerate(lines,1):
            if line.strip() and not re.match(r'^#{1,6} ',line) and not re.fullmatch(r'[-*_]{3,}',line.strip()):
                require(i in covered, f'unindexed source line: {s["id"]}:{i}')
    for item in index['excluded_files']:
        repo = repos[item['repository']]
        checkout = Path(overrides.get(repo['id'],repo['checkout_hint'])).expanduser()
        require(item['path'] not in paths[repo['id']], f'duplicate excluded file: {item["path"]}')
        paths[repo['id']].add(item['path'])
        require(sha(git(checkout,'show',repo['commit']+':'+item['path']))==item['sha256'],f'excluded hash mismatch: {item["path"]}')
        require(bool(item['reason']), f'exclusion missing reason: {item["path"]}')
    for repo in repos.values():
        checkout = Path(overrides.get(repo['id'],repo['checkout_hint'])).expanduser()
        require(git(checkout,'remote','get-url','origin').decode().strip()==repo['remote'],f'remote identity mismatch: {repo["id"]}')
        if repo['inventory_mode']=='all_tracked_files':
            tracked=set(git(checkout,'ls-tree','-r','--name-only',repo['commit']).decode().splitlines())
            require(tracked==paths[repo['id']],f'inventory mismatch: {repo["id"]}: {sorted(tracked ^ paths[repo["id"]])}')
    for edge in index['references']:
        require(edge['from_node'] in node_ids, f'dangling reference source: {edge["from_node"]}')
        for target in edge['targets']:
            require(target['source_ref'] in source_ids, f'dangling reference target: {target}')
            require('context_ref' not in target or target['context_ref'] in contexts,f'dangling target context: {target}')
    for gap in index['gaps']:
        shape(gap, 'gap')
        unique(gap['id'])
        require(gap['status'] in {'open', 'resolved'}, f'bad gap status: {gap["id"]}')
        require(bool(gap['node_refs']) and all(n in node_ids for n in gap['node_refs']),f'gap without source: {gap["id"]}')
        require(all(gap[k] for k in ['owner','impact','resolution_needed','explanation']),f'incomplete gap: {gap["id"]}')
    for case in cases['cases']:
        unique(case['id'])
        require(all(n in node_ids for n in case['node_refs']),f'case source missing: {case["id"]}')
        require(all(g in open_gaps for g in case['source_gap_refs']),f'case gap missing or resolved: {case["id"]}')
        require(not case['factor_refs'] and not case['route_refs'],f'step 2 must not claim factors/routes: {case["id"]}')
        require(case['status']=='selected_not_defined',f'case status mismatch: {case["id"]}')
    live_ids = set(ids)
    for retired in index['retired_ids']:
        require(set(retired) == {'id', 'replacement_ids', 'reason'}, f'bad retired record: {retired.get("id")}')
        unique(retired['id'])
        require(bool(retired['reason']), f'retirement reason missing: {retired["id"]}')
        require(all(ref in live_ids for ref in retired['replacement_ids']), f'retired replacement missing: {retired["id"]}')
    require(set(contract['verdicts'])=={'pass','fail','blocked','inconclusive','not_run'},'five verdicts required')
    require(contract['run_storage']['retention_days']>0,'retention must be concrete')
    require(not index['scope']['factors_created'],'step 2 factors flag must be false')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--repo', action='append', default=[], metavar='ID=PATH')
    args = parser.parse_args()
    root = args.root.resolve()
    index = load_yaml(root/'sources.yaml')
    cases = load_yaml(root/'representative_cases.yaml')
    contract = load_yaml(root/'contracts/minimum_contract.yaml')
    overrides = dict(item.split('=',1) for item in args.repo)
    errors = check(index,cases,contract,root,overrides)
    if errors:
        print('FAIL\n'+'\n'.join(errors),file=sys.stderr)
        return 1
    requirements = [c for s in index['sources'] for n in s['nodes'] for c in n['claims']]
    counts = collections.Counter(c['status'] for c in requirements)
    print(json.dumps({'check':'passed','sources':len(index['sources']),'nodes':sum(len(s['nodes']) for s in index['sources']),'requirements':len(requirements),'requirement_status':dict(counts),'gaps':len(index['gaps']),'gap_status':dict(collections.Counter(g['status'] for g in index['gaps'])),'cases':len(cases['cases']),'product_tests_executed':False},ensure_ascii=False))
    return 0

if __name__=='__main__':
    try:
        sys.exit(main())
    except (ValueError,KeyError,TypeError,OSError,subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}',file=sys.stderr)
        sys.exit(2)
