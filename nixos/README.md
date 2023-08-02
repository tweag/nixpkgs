# NixOS

NixOS is a Linux distribution based on the purely functional package
management system Nix.  More information can be found at
https://nixos.org/nixos and in the manual in doc/manual.

## (Reviewing contributions)

### Module updates {#reviewing-contributions-module-updates}

Module updates are submissions changing modules in some ways. These often contains changes to the options or introduce new options.

Reviewing process:

- Ensure that the module maintainers are notified.
  - [CODEOWNERS](https://help.github.com/articles/about-codeowners/) will make GitHub notify users based on the submitted changes, but it can happen that it misses some of the package maintainers.
- Ensure that the module tests, if any, are succeeding.
- Ensure that the introduced options are correct.
  - Type should be appropriate (string related types differs in their merging capabilities, `loaOf` and `string` types are deprecated).
  - Description, default and example should be provided.
- Ensure that option changes are backward compatible.
  - `mkRenamedOptionModuleWith` provides a way to make option changes backward compatible.
- Ensure that removed options are declared with `mkRemovedOptionModule`
- Ensure that changes that are not backward compatible are mentioned in release notes.
- Ensure that documentations affected by the change is updated.

Sample template for a module update review is provided below.

```markdown
##### Reviewed points

- [ ] changes are backward compatible
- [ ] removed options are declared with `mkRemovedOptionModule`
- [ ] changes that are not backward compatible are documented in release notes
- [ ] module tests succeed on ARCHITECTURE
- [ ] options types are appropriate
- [ ] options description is set
- [ ] options example is provided
- [ ] documentation affected by the changes is updated

##### Possible improvements

##### Comments
```

### New modules {#reviewing-contributions-new-modules}

New modules submissions introduce a new module to NixOS.

Reviewing process:

- Ensure that the module tests, if any, are succeeding.
- Ensure that the introduced options are correct.
  - Type should be appropriate (string related types differs in their merging capabilities, `loaOf` and `string` types are deprecated).
  - Description, default and example should be provided.
- Ensure that module `meta` field is present
  - Maintainers should be declared in `meta.maintainers`.
  - Module documentation should be declared with `meta.doc`.
- Ensure that the module respect other modules functionality.
  - For example, enabling a module should not open firewall ports by default.

Sample template for a new module review is provided below.

```markdown
##### Reviewed points

- [ ] module path fits the guidelines
- [ ] module tests succeed on ARCHITECTURE
- [ ] options have appropriate types
- [ ] options have default
- [ ] options have example
- [ ] options have descriptions
- [ ] No unneeded package is added to environment.systemPackages
- [ ] meta.maintainers is set
- [ ] module documentation is declared in meta.doc

##### Possible improvements

##### Comments
```
