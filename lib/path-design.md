# Design of the Path library

Goals:
- Write laws for functions
  - Makes behavior predictable and easily testable
- Works without filesystem access
  - Because we don't know where these paths will be used, eval-time, build-time or runtime
    - Also, Nix doesn't even support reading symlinks at eval-time
- Handles absolute and relative paths
- Takes either path or string Nix data types as input
  - Nix paths are easier to type, but they always resolve to absolute paths
  - So we need to allow strings to specify relative paths
- Returns string data types
  - Since path data types in Nix don't support relative paths

TODO:
- Add edge cases
- Add more language comparisons
- Add functions for splitting into basename and filename
- Add functions for handling extensions
- Add function for getting a common prefix
- (?) Needs to support prepending a prefix to an absolute path, needed for NixOS (see filesystems.nix)

## Design decisions:

### Representation

Paths are represented as strings, not as attribute sets with specific attributes, because:
- It's simpler
- It's faster
- `+` is convenient but doesn't work on attribute sets
  - It works if we add `__toString` attributes, but then all other attributes get wiped

### Parents

`..` or a `parent` function is not supported, because:
- It requires resolving symlinks to have proper behavior, since e.g. `foo/..` would not be the same as `.` if `foo` is a symlink
  - And we can't resolve symlinks without filesystem access
- This would be problematic for functions like `relativeTo` or `hasParent`
- While we could just allow ".." in the beginning like "../foo", this then leads to having to throw an error for doing `join [ "/some/path" "../foo" ]`
- We argue that `..` is not needed at the Nix evaluation level, since we'd always start evaluation from the project root and don't go up from there
  - And `..` is supported in Nix paths (which turns them into absolute paths)
- If you need `..` for building or runtime, you can use build/run-time tooling to create those (e.g. `realpath` with `--relative-to`), or use absolute paths instead

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

Use cases:
- TODO

### `split`

Splits a path into its components. Only if the path is absolute, the first component is a `/`

Examples:
- `split "/" == ["/"]`
- `split "/foo" == ["/" "foo"]`
- `split "." == []`
- `split "bar" == ["foo"]`

Laws:
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
