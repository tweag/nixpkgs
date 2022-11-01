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

## Design decisions

### Representation

Paths are represented as strings, not as attribute sets with specific attributes:

+ It's simpler
+ It's faster
+ `+` is convenient and doesn't work on attribute sets
  - It works if we add `__toString` attributes
    + But then all other attributes get wiped

### Parents

`..` path components are not supported, nor as inputs nor as outputs. For similar reasons there's no `parent` function.

+ It requires resolving symlinks to have proper behavior, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink.
  + We can't resolve symlinks without filesystem access
  + Nix doesn't support reading symlinks at eval-time
- We could allow ".." just in the beginning
  + Then we'd have to throw an error for doing `join [ "/some/path" "../foo" ]`, making it non-composable
  + The same is for returning paths with `..`: `relativeTo "/foo" "/bar" => "../foo"` would produce a non-composable path
+ We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there
  + And `..` is supported in Nix paths (which turns them into absolute paths)
+ If you need `..` for building or runtime, you can use build/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead

Why no ".."?
- For Nix eval time paths, we don't need them, because Nix does resolve paths absolutely, and we don't have access the filesystem
- For build/runtime paths, we can't do much path processing without being able to inspect the filesystem. You can use readlink or other libraries to resolve paths there

### Trailing slashes

Trailing slashes are not persisted, because:
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
- `split "bar" == ["foo"]`

Invariants:
- Inverse of `join`:
  `join (split p) == normalise p`
- Components can't be split any further:
  `! exists cs . join cs == p && length cs > length (split p)`
- TODO: Law that ensures components are normalized?

Use cases:
- TODO

Other languages:
- [Rust](https://doc.rust-lang.org/std/path/struct.PathBuf.html#method.components)
- [Python](https://docs.python.org/3/library/pathlib.html#pathlib.PurePath.parts)
- [Haskell](https://hackage.haskell.org/package/filepath-1.4.100.0/docs/System-FilePath.html#v:splitDirectories)

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

Normalizes the path: Removes extraneous `/./`'s and `//`'s, removes trailing slashes, errors for empty strings. Errors for strings containing "..". Doesn't read from the filesystem and doesn't follow symbolic links.

Examples:
- `normalise "///foo/./bar//" == "/foo/bar"`
- `normalise "//" == "/foo/bar"`

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

Other languages:
- [Nodejs](https://nodejs.org/api/path.html#pathnormalizepath)
- [POSIX Pathnames](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html#tag_03_271)
- [POSIX Pathname Resolution](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13)
