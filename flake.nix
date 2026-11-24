{
	description = "Ladybird browser, built from this fork";

	inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

	outputs = { self, nixpkgs }:
		let
			systems = [
				"x86_64-linux"
				"aarch64-linux"
			];
			forSystems = nixpkgs.lib.genAttrs systems;
			date = self.lastModifiedDate or "19700101000000";
			version = "0-unstable-${builtins.substring 0 4 date}-${builtins.substring 4 2 date}-${builtins.substring 6 2 date}";
			ladybirdFor = pkgs: pkgs.callPackage ./nix/package.nix {
				src = self;
				inherit version;
			};
		in
		{
			packages = forSystems (system: rec {
				ladybird = ladybirdFor nixpkgs.legacyPackages.${system};
				default = ladybird;
			});

			overlays.default = final: prev: {
				ladybird = ladybirdFor final;
			};
		};
}
