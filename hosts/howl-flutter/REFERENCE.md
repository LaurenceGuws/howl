# Inactive Flutter bring-up reference

This directory is historical engineering evidence while Flutter is rewritten in
the separate howl-sessions product. It is **not an active Howl host**.

- Do not invoke its build, install, Dart, iOS, or native FFI entrypoints.
- Do not pin new Howl core APIs to make this historical tree compile.
- It is not in the root build graph, release inventory or tested snapshot.
- The exact native package-root exception in tools/audit_project.sh is temporary
  and must not generalize to another package.

The previous bring-up proved behavior worth studying; it is not a compatibility
promise. Git history preserves that work even after this copybook is retired.
