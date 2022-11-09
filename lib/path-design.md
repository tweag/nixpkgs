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

### Leading dots for relative paths
[leading-dots]: #leading-dots-for-relative-paths

Normalised relative paths should always have a leading `./`:

+ In shells, just running `foo` as a command wouldn't execute the file `foo`, whereas `./foo` would execute the file. In contrast, `foo/bar` does execute that file without the need for `./`. This can lead to confusion about when a `./` needs to be prefixed. If a `./` is always included, this becomes a non-issue. This effectively then means that paths don't overlap with command names.
+ Using paths in command line arguments could give problems if not escaped properly, e.g. if a path was `--version`. This is not a problem with `./--version`. This effectively then means that paths don't overlap with GNU-style command line options
- The POSIX standard doesn't require `./`
- It's more pretty without the `./`, good for error messages and co.
  + But similarly, it could be confusing whether something was even a path
    e.g. `foo` could be anything, but `./foo` is more clearly a path
+ Makes it more uniform with absolute paths (those always start with `/`)
  - Not relevant though, this perhaps only simplifies the implementation a tiny bit
+ Makes even single-component relative paths (like `./foo`) valid as a path expression in Nix (`foo` wouldn't be)
  - Not relevant though, we won't use these paths in Nix expressions
+ `find` also outputs results with `./`
  - But only if you give it an argument of `.`. If you give it the argument `some-directory`, it won't prefix that
- `realpath --relative-to` doesn't output `./`'s

Conclusion: There's some weak arguments for not having `./`, but there's some strong arguments for having it (the first two), so we're going to have it.

### Representation of the current directory

Should it be `.`, `./` or `./.`?
- `.`: Would be the only path without a `/` and therefore not a valid Nix path in expressions
  + We don't require people to type this in expressions
- `.`: Can be interpreted as a shell command (it's a builtin command for zsh)
- `./`: Inconsistent with [the decision to not have trailing slashes](trailing-slashes)
- `./.`: Is rather long
  + We don't require users to type this though, it's only used as a library output. As inputs all three variants are supported

Conclusion: Should be `./.`

### `split` being part of the public API

`split` is an function to split a path into its components, `join` is the inverse operation. Arguments for `split` being part of the public API:
+ We don't want to encourage custom path handling, which `split` enables
  - If there's a need for it, people will do custom handling either way. `split` is a primitive that can make this safer
- We might not be able to cover all use cases with our path library

Conclusion: It should be part of the public API

### Representation

Paths are represented as strings, not as attribute sets with specific attributes:

+ It's simpler
+ It's faster
  - Unless you need to do certain path operations in sequence, e.g. `join [ (join [ "/foo" "bar" ]) "baz" ]` needs the inner `join` to return a string composed of its arguments, only for that string to be decomposed again in the outer `join`
    + We can mostly avoid such costs by exporting sufficiently powerful functions, so that users don't need to make multiple roundtrips to the library representation
+ `+` is convenient and doesn't work on attribute sets
  - It works if we add `__toString` attributes
    + But then all other attributes get wiped

### Parents
[parents]: #parents

`..` path components are not supported, nor as inputs nor as outputs.

+ It requires resolving symlinks to have proper behavior, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink.
  + We can't resolve symlinks without filesystem access
  + Nix doesn't support reading symlinks at eval-time
  - What is "proper behavior"? Why can't we just not handle these cases?
    + E.g. `equals "/foo" "/foo/bar/.."` should those paths be equal?
      - That can just return `false`, the paths are different, we don't need to check whether the paths point to the same thing
    + E.g. `relativeTo "/foo" "/bar" == "../foo"`. If this is used like `/bar/../foo` in the end and `bar` is a symlink to somewhere else, this won't be accurate
      - We could not support such ambiguous operations, or mark them as such, e.g. the normal `relativeTo` will error on such a case, but there could be `extendedRelativeTo` supporting that
- `..` are a part of paths, a path library should therefore support it
  + If we can prove that all such use cases are better done e.g. with runtime tools, the library not supporting it can nudge people towards that
    - Can we prove that though?
- We could allow ".." just in the beginning
  + Then we'd have to throw an error for doing `join [ "/some/path" "../foo" ]`, making it non-composable
  + The same is for returning paths with `..`: `relativeTo "/foo" "/bar" => "../foo"` would produce a non-composable path
+ We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there
  + And `..` is supported in Nix paths (which turns them into absolute paths)
  - But we don't know whether these paths will be used at the Nix evaluation level, they could be for build/runtime
+ If you need `..` for building or runtime, you can use build/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead

Why no ".."?
- For Nix eval time paths, we don't need them, because Nix does resolve paths absolutely, and we don't have access the filesystem
- For build/runtime paths, we can't do much path processing without being able to inspect the filesystem. You can use readlink or other libraries to resolve paths there

### Trailing slashes
[trailing-slashes]: #trailing-slashes

Context: Paths can contain trailing slashes, like `foo/`.
Often this indicates that `foo` is a directory and not a file.
It's effectively the same path as just `foo` though.
This library normalises all paths by removing trailing slashes

Arguments for (+) and against (-) this decision:
- + Most languages don't preserve them:
  - Rust doesn't preserve them during normalisation
  - Python doesn't preserve them


- Check other languages (TODO: Link to documentation / arguments)
  - Nix doesn't allow them in the path data type
  - Rust doesn't persist them when normalizing path strings
  - Python doesn't preserve them
  - Haskell does preserve them
- Paths with an ending `/` make Nix's `baseNameOf` and `dirOf` behave weird:
  - `baseNameOf "/foo/bar/" == "bar"`
  - `dirOf "/foo/bar/" == "/foo/bar"`
  - Though the path library would have its own way of achieving this

TODO: Check with the Nix community

#### Disadvantages and counterarguments
- Can't do `normalise ("/foo" + "/") + "bar"`
  - Why would you want to do that?
  - We need a `join` method anyways
  - Could also not represent paths as strings, so that + doesn't even work
    - But if `__toString` is used, can still use `+` regardless
- `realpath` 
- `normalise` might return different results even if it's the same path, due to a trailing slash!
  - `normalise` should return the same result
TODO: In docs, discourage users from converting output strings into Nix paths, as this will invoke Nix's broken path handling.

union ./. [
  ./foo
  ./bar
  "foo"
  "bar"
]

union (join [ ./. "foo" ]) [ ../foo ] => error

/. + "/some/thing"

join [ "/mnt" "/home/infinisil" ] -> <error>

join [ "/mnt" (relativeTo "/" "/home/infinisil") ]

- Write laws for functions
  - Makes behavior predictable and easily testable

Future:
- Path library, no filesystem access
- filesystem library, filesystem access, but doesn't import into the store
- sources library, imports into the store

projectRoot = ./.

projectRoot = ../foo



TODO:
- Add edge cases
- Add more language comparisons
- Add functions for splitting into basename and filename
- Add functions for handling extensions
- Add function for getting a common prefix
- (?) Needs to support prepending a prefix to an absolute path, needed for NixOS (see filesystems.nix)


## API

TODO:
- baseNameOf
- dirOf
- isRelativeTo
- commonAncestor
- equals
- extension handling
- List of all ancestors (including self)

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

TODO: do the arguments have to be absolute paths?

Use cases:
- setSubpath ./foo/bar ./.
- setSubpath /home/infinisil/foo/bar /home/infinisil
- Given an absolute path from Nix, make it relative:
  `relativeTo ./. ./foo/bar => "foo/bar"`

- join [ /mnt (relativeTo / /home/alice) ]

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
