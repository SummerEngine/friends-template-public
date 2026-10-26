# Hosted graph budget

The hosted analyzer (Summer 0.7.x, `SummerWorldCompositionAnalyzer`) reads `world.json`, then `source-domains.json`, and walks the
declared roots. Limits that matter here:

| Limit | Value | Where it bites |
|---|---|---|
| files per profile | 4096 | every file below a directory root counts, sidecars (`.uid`, `.import`) included |
| paths per domain row | 128 | a row lists directories and single files; unrelated root-level files each cost one path |
| dependency edges | 512 | `dependencies` of the graph file |
| one file | 16 MiB, whole graph 256 MiB | |

`tools/build_domain_graph.py` computes the graph and checks these limits before any engine starts (see `docs/build-tooling.md`).
The clone is pruned to what the entry scenes reach, so unused models, textures and scripts never count.

## Analyzer rules the code has to respect

* Every `res://` token in a declared text file must name a declared file. Comments and JSON count; a trailing `.` or a directory
  name is part of the token and fails. A run-time prefix is written `"res" + "://dir/"`.
* `load()`/`preload()` (and `ResourceLoader.load()`) whose first argument is not a string literal is a *computed load* and needs a
  declared dependency edge. The generator adds the edge to the role's resource manifest. `load(CONST)` of a shader or font in shared
  code is a computed load as well: use a literal `preload`.
* Shared code cannot depend on client files, client code can depend on shared; both authority and client profiles are analyzed.
* Shared and client code must not branch on the runtime role or use raw RPCs; authority files must not touch UI, input, audio or
  rendering APIs (the scan reads comments too).
* `uid://` tokens must resolve to a declared `.uid` owner; `.import` UIDs are copied to `.uid` sidecars in the clone.

## What the generator keeps the budget with

* Pruning: files no entry reaches are deleted from the clone; city-kit models are kept by the names shipped scripts and level data use.
* Directory roots wherever a whole directory has one role. Keep directories single-role (shared code, client code and authority code
  in separate directories) and keep the project root nearly empty: root-level files cannot be grouped.
* Payload manifests: `assets/shared_resources.json`, `assets/client_resources.json`, `assets/authority_resources.json` list
  payload files, so one edge per computed-load script covers every file it may load.

Typical report (`tools/build_domain_graph.py --project demo`): per-row path counts, edge count, file counts of both profiles, the
computed-load scripts, notes about presentation files named from shared code, and files no entry reaches.
