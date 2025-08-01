{
  description = "Pulumi and packer automation for XCP-ng";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ];
          # Needed for packer BUSL
          config.allowUnfree = true;
        };
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            uv
            pyright
            ruff
            pulumi-bin
            packer
          # uv manages its own python version by default
          # but you can target a specific python version
          # if you really want (see uv docs)
          #  (python312.withPackages (
          #    ps: with ps; [
          #      pyflakes
          #      isort
          #    ]
          #  ))
          ];
        };
      }
    ));
}
