# File sets {#sec-fileset}

The [`lib.fileset`](#sec-functions-library-fileset) functions allow you to work with _file sets_.
File sets efficiently represent a precise set of local files that should be imported into the Nix store and be available to a derivation.
They can easily be created and combined for complex behavior.

## Implicit coercion from paths to file sets {#sec-fileset-path-coercion}

All functions accepting file sets as arguments can also accept [paths](https://nixos.org/manual/nix/stable/language/values.html#type-path) as arguments.
Such paths arguments are implicitly coerced to file sets containing all files under that path:
- A path to a file turns into a file set containing that single file.
- A path to a directory turns into a file set containing all files _recursively_ in that directory.

If the path points to a non-existent location, an error is thrown.

::: {.note}
File sets cannot represent empty directories.
Because of this, a path to a directory that contains no files (recursively) will turn into a file set containing no files.
:::

### Example {#sec-fileset-path-coercion-example}

Assume we are in a local directory with a file hierarchy like this:
```
├── filledDir/
│   ├── nestedFile
│   └── nestedDir/
│       └── doublyNestedFile
└── emptyDir/
    └── emptySubdir/
```

Here's what files each path expression get included when coerced to a file set:
- `./filledDir` turns into a file set containing both `filledDir/nestedFile` and `filledDir/nestedDir/doublyNestedFile`
- `./filledDir/nestedFile` turns into a file set containing only `filledDir/nestedFile`
- `./filledDir/nestedDir` turns into a file set containing only `filledDir/nestedDir/doublyNestedFile`
- `./emptyDir` turns into an empty file set
- `./emptyDir/emptySubdir` turns into an empty file set

## TODO {#sec-fileset-todo}

This document should have a section or paragraph for each of these points:
- Currently there's only very few functions, to be expanded
- If you pass the same arguments to the same functions, you will get the same file set, context-free
- Empty directories aren't included
- Internal representation, file sets cannot be evaluated directly
- Multiple representations for the same file set (`"directory"` vs `readDir p`). Equality using `==` doesn't work
- Performance of operations
- Nothing is imported by operations, even though path expressions are used, which would be imported into the store when interpolated in strings
- Tracked which files can influence the result
- Changing the root doesn't influence the set of files included, no need to be worried about including too much.
- Files need to exist
