- SyntaxNodes are either mutable or not
- We want them to be mutable, but only when we actually intend on changing them
  This means, only for the `migrate` command, and only for the attr name location files, not the reference check files
- We should be able to re-render the file without needing backward-replacements
- Mutable syntax nodes can be changed without absolute locations/indices. So any absolute locations need to be resolved before modifying it
