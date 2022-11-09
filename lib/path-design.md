# Design of the Path library

## Goals

- Work without filesystem access

  We don't know where these paths will be used, eval-time, build-time or runtime.

- Handle absolute and relative paths

- Take path or string Nix data types as input

  Nix paths are convenient if you need to refer to project-local files, since they resolve relatively to the Nix file they are declared in.

  However, they always resolve to absolute paths.
  We need strings to allow specifying relative paths.

- Returns string data types

  Since Nix paths don't support relative paths and they mangle ".."

- Don't allow ambiguous paths

  We don't know how these paths are used in the end.
  When symlinks are involved, paths containting `..` may produce unexpected results.

  TODO: Alternatively, something like "Ignoring symlinks, every filesystem location under an anchor (either / or .) has exactly one normalised path pointing to it"

  TODO: Do we really want this though? See the `..` discussion below

## Implementation notes

In this library's main docs, discourage users from converting output strings into Nix paths, as this will invoke Nix's broken path handling.

This library is only the first step towards a full filesystem handling library, consisting of three parts:
- `lib.path`: no filesystem access, works with eval-/build-/run-time paths
- `lib.filesystem`: filesystem access, but doesn't import into the store, only works with eval-time paths
- `lib.sources`: imports eval-time paths into the store

## Use cases
- [Source combinators](https://github.com/NixOS/nixpkgs/pull/112083)

## Other implementations and references

- [Rust](https://doc.rust-lang.org/std/path/struct.PathBuf.html)
- [Python](https://docs.python.org/3/library/pathlib.html)
- [Haskell](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html)
- [Nodejs](https://nodejs.org/api/path.html#pathnormalizepath)
- [POSIX Pathnames](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_271)
- [POSIX Pathname Resolution](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13)

## General design decisions

Each subsection here contains a decision along with arguments and counter-arguments for (+) and against (-) that decision.

### Leading dots for relative paths
[leading-dots]: #leading-dots-for-relative-paths

Context: Relative paths can have a leading `./` to indicate it being a relative path, this is generally not necessary for tools though

Decision: Returned relative paths should always have a leading `./`

- \+ In shells, just running `foo` as a command wouldn't execute the file `foo`, whereas `./foo` would execute the file. In contrast, `foo/bar` does execute that file without the need for `./`. This can lead to confusion about when a `./` needs to be prefixed. If a `./` is always included, this becomes a non-issue. This effectively then means that paths don't overlap with command names.
- \+ Using paths in command line arguments could give problems if not escaped properly, e.g. if a path was `--version`. This is not a problem with `./--version`. This effectively then means that paths don't overlap with GNU-style command line options
- \- The POSIX standard doesn't require `./`
- \- It's more pretty without the `./`, good for error messages and co.
  - \+ But similarly, it could be confusing whether something was even a path
    e.g. `foo` could be anything, but `./foo` is more clearly a path
- \+ Makes it more uniform with absolute paths (those always start with `/`)
  - \- Not relevant though, this perhaps only simplifies the implementation a tiny bit
- \+ Makes even single-component relative paths (like `./foo`) valid as a path expression in Nix (`foo` wouldn't be)
  - \- Not relevant though, we won't use these paths in Nix expressions
- \+ `find` also outputs results with `./`
  - \- But only if you give it an argument of `.`. If you give it the argument `some-directory`, it won't prefix that
- \- `realpath --relative-to` doesn't output `./`'s
- \- Leads to `split [ "/foo/bar" ] == [ "/" "./foo" "./bar" ]`, which is a bit verbose
  - \+ Why does that matter?

TODO: Update the library and this document with this decision

### UNC paths
[unc]: #unc-paths

TODO: Paths starting with exactly two slashes (`//`) can have implementation-defined meaning

### Representation of the current directory
[curdir]: #representation-of-the-current-directory

Context: The current directory can be represented with `.` or `./` or `./.`

Decision: It should be `./.`

- \+ `.` would be the only path without a `/` and therefore not a valid Nix path in expressions
  - \- We don't require people to type this in expressions
- \+ `.` can be interpreted as a shell command (it's a builtin command for zsh)
- \+ `./` inconsistent with [the decision to not have trailing slashes](#trailing-slashes)
- \- `./.` is rather long
  - \+ We don't require users to type this though, it's only used as a library output.
    As inputs all three variants are supported

### `split` being part of the public API
[public-split]: #split-being-part-of-the-public-api

Context: The main use case for `split` seems to be internal to the library and might not need to be exposed as a public API.
The inverse `join` does have lots of use cases though (it appends path components), so it should definitely be part of the public API

Decision: `split` should be part of the public API

- \- We don't want to encourage custom path handling, which `split` enables
  - \+ If there's a need for it, people will do custom handling either way. `split` is a primitive that can make this safer
- \+ We might not be able to cover all use cases with our path library

### Representation
[representation]: #representation

Context: Paths can be represented directly as a string, or as an attribute set like `{ components = [ "foo" "bar" ]; anchor = "/"; }`

Decision: Paths are represented as strings

- \+ It's simpler
- \+ It's faster
  - \- Unless you need to do certain path operations in sequence, e.g. `join [ (join [ "/foo" "bar" ]) "baz" ]` needs the inner `join` to return a string composed of its arguments, only for that string to be decomposed again in the outer `join`
    - \+ We can mostly avoid such costs by exporting sufficiently powerful functions, so that users don't need to make multiple roundtrips to the library representation
- \+ `+` is convenient and doesn't work on attribute sets
  - \- It works if we add `__toString` attributes
    - \+ But then all other attributes get wiped
    - \+ And we'd then be able to `+` paths again

### Parents
[parents]: #parents

Context: Paths can have `..` components, which refer to the parent directory

Decision: `..` path components are not supported, nor as inputs nor as outputs.

- \+ It requires resolving symlinks to have proper behavior, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink.
  - \+ We can't resolve symlinks without filesystem access
  - \+ Nix also doesn't support reading symlinks at eval-time
  - \- What is "proper behavior"? Why can't we just not handle these cases?
    - \+ E.g. `equals "/foo" "/foo/bar/.."` should those paths be equal?
      - \- That can just return `false`, the paths are different, we don't need to check whether the paths point to the same thing
    - \+ E.g. `relativeTo "/foo" "/bar" == "../foo"`. If this is used like `/bar/../foo` in the end and `bar` is a symlink to somewhere else, this won't be accurate
      - \- We could not support such ambiguous operations, or mark them as such, e.g. the normal `relativeTo` will error on such a case, but there could be `extendedRelativeTo` supporting that
- \- `..` are a part of paths, a path library should therefore support it
  - \+ If we can prove that all such use cases are better done e.g. with runtime tools, the library not supporting it can nudge people towards that
    - \- Can we prove that though?
- \- We could allow ".." just in the beginning
  - \+ Then we'd have to throw an error for doing `join [ "/some/path" "../foo" ]`, making it non-composable
  - \+ The same is for returning paths with `..`: `relativeTo "/foo" "/bar" => "../foo"` would produce a non-composable path
- \+ We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there
  - \+ And `..` is supported in Nix paths, turning them into absolute paths
    - \- This is ambiguous with symlinks though
- \+ If you need `..` for building or runtime, you can use build/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead.
  This also gives you the ability to correctly handle symlinks

### Trailing slashes
[trailing-slashes]: #trailing-slashes

Context: Paths can contain trailing slashes, like `foo/`, indicating that the path points to a directory and not a file

Decision: All functions remove trailing slashes in their results

- Comparison to other frameworks to figure out the least surprising behavior:
  - \+ Nix itself doesn't preserve trailing newlines when parsing and appending its paths
  - \- [Rust's std::path](https://doc.rust-lang.org/std/path/index.html) does preserve them during [construction](https://doc.rust-lang.org/std/path/struct.Path.html#method.new)
    - \+ Doesn't preserve them when returning individual [components](https://doc.rust-lang.org/std/path/struct.Path.html#method.components)
    - \+ Doesn't preserve them when [canonicalizing](https://doc.rust-lang.org/std/path/struct.Path.html#method.canonicalize)
  - \+ [Python 3's pathlib](https://docs.python.org/3/library/pathlib.html#module-pathlib) doesn't preserve them during [construction](https://docs.python.org/3/library/pathlib.html#pathlib.PurePath)
    - Notably it represents the individual components as a list internally
  - \- [Haskell's filepath](https://hackage.haskell.org/package/filepath-1.4.100.0) has [explicit support](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#g:6) for handling trailing slashes
    - \- Does preserve them for [normalisation](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#v:normalise)
  - \- [NodeJS's Path library](https://nodejs.org/api/path.html) preserves trailing slashes for [normalisation](https://nodejs.org/api/path.html#pathnormalizepath)
    - \+ For [parsing a path](https://nodejs.org/api/path.html#pathparsepath) into its significant elements, trailing slashes are not preserved
- \+ Nix's builtin function `dirOf` gives an unexpected result for paths with trailing slashes: `dirOf "/foo/bar/" == "/foo/bar"`.
  Inconsistently, `baseNameOf` works correctly though: `baseNameOf "/foo/bar/" == "bar"`.
  - \- We are writing a path library to improve handling of paths though, so we shouldn't use these functions and discourage their use
- \- Unexpected result when normalising intermediate paths, like `normalise ("/foo" + "/") + "bar" == "/foobar"`
  - \+ Does this have a real use case?
  - \+ Don't use `+` to append paths, this library has a `join` function for that
    - \- Users might use `+` instinctively though
- \+ The `realpath` command also removes trailing slashes
- \+ Even with a trailing slash, the path is the same, it's only an indication that it's a directory
- \+ Normalisation should return the same string when we know it's the same path, so removing the slash.
  This way we can use the result as an attribute key.

TODO:
- Add more language comparisons

## API

TODO:
- baseNameOf
- dirOf
- isRelativeTo
- commonAncestor
- equals
- extension handling
- List of all ancestors (including self), like <https://doc.rust-lang.org/std/path/struct.PathBuf.html#method.ancestors>

### `isAbsolute`

Whether a path is absolute

Examples:
- `IsAbsolute "/" == true`
- `IsAbsolute "/foo" == true`
- `IsAbsolute "." == false`
- `IsAbsolute "bar" == false`

Use cases:
- TODO

### `isRelative`

Whether a path is relative. This is the boolean inverse of `isAbsolute`

### `relativeTo`

Turns an absolute path into a relative path

Examples:
- `relativeTo "/foo" "/foo/bar" == "bar"`
- `relativeTo "/baz" "/foo/bar" == <error>`
- `relativeTo "foo" "foo/bar" == "bar"`
- `relativeTo "foo" "/foo/bar" == <error>`
- `relativeTo "/" "/foo/bar" == "foo/bar"`

TODO: do the arguments have to be absolute paths?

Use cases:
- setSubpath ./foo/bar ./.
- setSubpath /home/infinisil/foo/bar /home/infinisil
- Given an absolute path from Nix, make it relative:
  `relativeTo ./. ./foo/bar => "foo/bar"`

### `split`

Splits a path into its components. Only if the path is absolute, the first component is a `/`

Examples:
- `split "/" == ["/"]`
- `split "/foo" == ["/" "foo"]`
- `split "." == []`
- `split "bar" == ["bar"]`

Invariants:
- Inverse of `join`:
  `join (split p) == normalise p`
- Components can't be split any further:
  `! exists cs . join cs == p && length cs > length (split p)`
- TODO: Law that ensures components are normalized?

Use cases:
- TODO

### `join`

Joins path components together. All but the first component must be relative, though they can contain non-leading slashes.

Examples:
- `join ["/foo" "bar"] == "/foo/bar"`
- `join ["foo" "bar/baz"] == "foo/bar/baz"`
- `join ["/foo" "/bar"] == <error>`
- `join ["/foo" (relativeTo "/" "/bar") ] == "/foo/bar"`

Laws:
- Inverse of `split`:
  `join (split p) == normalise p`
- Associativity (TODO: Why do we need this?):
  `join [ (join [a b]) c ] == join [ a (join [b c]) ]`
- The result is normalised:
  join as == normalise (join as)

Use cases:
- TODO

### `normalise`

Normalizes the path by:
- Limiting repeating `/` to a single one (does not change a [POSIX Pathname](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_271))
- Removing extraneous `.` components (does not change the result of [POSIX Pathname Resolution](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13))
- Erroring for empty strings (not allowed as a [POSIX Filename](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_170))
- Removing trailing `/` and `/.` (See [justification](#trailing-slashes))
- Erroring for ".." components (See [justification](#parents))
- Prefixing relative paths with `./` (See [justification](#leading-dots))

Examples:
- `normalise "foo" == "./foo"`
- `normalise "/foo//bar" == "/foo/bar"`
- `normalise "/foo/./bar" == "/foo/bar"`
- `normalise "" == <error>"`
- `normalise "/foo/" == "/foo"`
- `normalise "/foo/." == "/foo"`
- `normalise "/foo/../bar" == <error>`
- `normalise "//foo" == "/foo"`
- `normalise "///foo" == "/foo"`
- `normalise "//././//foo/.//.///bar/." == "/foo/bar"`

Laws:
- Same as splitting and joining:
  join (split p) == normalise p
- Idempotency:
  `normalise (normalise p) == normalise p`
- Behaves like `realpath`:
  `isAbsolute p => normalise p == realpath --no-symlinks --canonicalize-missing p`
  `isRelative p => normalise p == realpath --no-symlinks --canonicalize-missing --relative-to=. p`

Use cases:
- As an attribute name for a path -> value lookup attribute set
  - E.g. `environment.etc.<path>`
- Path equality comparison 
