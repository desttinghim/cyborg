final: prev: rec { 
  devShell = prev.callPackage ./devshell.nix { };

  zig = final.zigpkgs.master;
}
