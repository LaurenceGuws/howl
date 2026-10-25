# Independent core package release manifests

`tools/package-release PACKAGE COMMIT OUTPUT_DIRECTORY` archives one exact
tracked core package. Base packages (PTY, VT, Text) retain their source
`build.zig.zon` unchanged. Render and Instance use the matching overlay so
their distributed packages pin exact published dependency assets and Zig
package hashes rather than sibling checkout paths.

Each release asset is immutable. The tool refuses to overwrite a filename.
Publication order follows the dependency graph:

1. PTY, VT, Text (no Howl dependencies)
2. Render (pinned VT and Text)
3. Instance (pinned PTY, VT, Text and Render)

Version numbers live in the original module manifests; publication tags add
an independently increasing release revision. An overlay's version and
fingerprint must match its source module. Test the resulting archive as a
standalone Git root and validate `zig fetch` before attaching it to a tag.

The source checkout remains convenient for developing multiple modules at
once; a **released** module never needs that checkout.
