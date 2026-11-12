final: prev: {
  chef-purifier = {
    readLock = import ./read-lock.nix { lib = final; };
  };
}
