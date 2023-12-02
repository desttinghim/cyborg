final: prev: rec { 
  devShell = prev.callPackage ./devshell.nix { };

  zig = final.zigpkgs."0.11.0";
}
