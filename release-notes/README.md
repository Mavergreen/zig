# Release notes

The generator (`release-notes.sh`, from shipyard) writes the notes file for every release: the title, a
"What changed" section (with a link to Zig's own release notes for a new upstream, from
`build/upstream-release-notes-url.sh`), a "Build ingredients" section when a pin moved, and the footer.
That one file, `dist/RELEASE_NOTES.md`, becomes the GitHub Release body and both Sparkle feeds'
`<description>`s (`zig.xml` and `zig-cross.xml`): the same bytes, read three times.

The footer's install-floor line describes the native pkg (`--min-os 10.9.5`), the one 10.9 users
install. The cross pkg's own minimum (macOS 11; it runs on Apple Silicon and only targets 10.9) lives
in `zig-cross.xml`, through its own `sign_and_appcast.sh --min-os 11.0`. The notes describe the product,
and each feed describes the artifact it serves.

A file here named `<full-version>.md` (e.g. `0.17.0-mavericks.1.md`) is OPTIONAL hand-written prose
for that one release. When present, it is inserted verbatim right after the generated title. It must
NOT start with its own `## ` heading, since the generator already emits the title.

Most releases have no file here, and that's fine: the generator's own sections are the whole note.
