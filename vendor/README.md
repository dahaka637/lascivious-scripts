# vendor/

Memory of every third-party mod bundled inside Lascivious Scripts — see section 12 of
[`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

Empty today: no third-party module has been integrated yet. Once one is, it gets its own directory
here:

```
vendor/<module_key>/
├── manifest.yml
├── upstream/            # pristine copy of the version actually integrated, never edited
├── INTEGRATION.md
├── LOCAL_CHANGES.md
└── TRANSLATION_PTBR.md
```

Own-code modules (`time-vote`, `zombie-decay`, and any future module written from scratch for this
pack) do **not** get a folder here — there is no upstream to snapshot. Their documentation lives in
`../docs/modules/<module_key>.md` instead, and they're still listed in `../docs/MODULE_REGISTRY.md`
with `Upstream: próprio`.

Never hand-edit files inside `vendor/<module_key>/upstream/` — that copy exists purely so a future
update can diff old-upstream vs. new-upstream vs. our bundled version. See the update flow in
section 18 of the architecture doc.
