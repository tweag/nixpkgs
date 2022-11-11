
  isRelativeTo = base: path:
    let
      baseComponents = split base;
      pathComponents = split path;
    in baseComponents == sublist 0 (length baseComponents) pathComponents;

  relativeTo = base: path:
    let
      baseComponents = split base;
      pathComponents = split path;
    in
    if baseComponents != sublist 0 (length baseComponents) pathComponents then throw "nope"
    else sublist (length baseComponents) (length pathComponents) pathComponents;

  commonAncestor = as: bs:
    let
      aComponents = split as;
      bComponents = split bs;
      go = i:
        if i < length aComponents && i < length bComponents && elemAt aComponents i == elemAt bComponents i
        then go (i + 1)
        else i;
      # TODO: absolute vs relative paths
    in sublist 0 (go 0) aComponents;

