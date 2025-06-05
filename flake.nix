{
    inputs = {
        ihp.url = "github:digitallyinduced/ihp";
        nixpkgs.follows = "ihp/nixpkgs";
        flake-parts.follows = "ihp/flake-parts";
        devenv.follows = "ihp/devenv";
        systems.follows = "ihp/systems";
        garnix-lib = {
            url = "github:garnix-io/garnix-lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs@{ self, nixpkgs, ihp, flake-parts, systems, garnix-lib, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {

            systems = import systems;
            imports = [ ihp.flakeModules.default ];

            perSystem = { pkgs, ... }: {
                ihp = {
                    # appName = "app"; # Available with v1.4 or latest master
                    enable = true;
                    projectPath = ./.;
                    packages = with pkgs; [
                        # Native dependencies, e.g. imagemagick
                    ];
                    haskellPackages = p: with p; [
                        # Haskell dependencies go here
                        p.ihp
                        cabal-install
                        base
                        wai
                        text

                        # Uncomment on local development for testing
                        # hspec
                    ];
                };

                # Custom configuration that will start with `devenv up`
                devenv.shells.default = {
                    # Start Mailhog on local development to catch outgoing emails
                    # services.mailhog.enable = true;

                    # Custom processes that don't appear in https://devenv.sh/reference/options/
                    processes = {
                        # Uncomment if you use tailwindcss.
                        # tailwind.exec = "tailwindcss -c tailwind/tailwind.config.js -i ./tailwind/app.css -o static/app.css --watch=always";
                    };
                };
            };

            flake.nixosConfigurations."production" = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = inputs;
                modules = [
                    garnix-lib.nixosModules.garnix
                    ihp.nixosModules.appWithPostgres
                    ({ lib, pkgs, ... }: {
                        garnix.server.enable = true;
                        networking.firewall = {
                            enable = true;
                            allowedTCPPorts = [ 22 80 443 ];
                        };

                        security.acme.defaults.email = "letsencrypt@digitallyinduced.com";
                        security.acme.acceptTerms = true;

                        environment.systemPackages = with pkgs; [ vim ];
                        programs.vim.enable = true;

                        services.ihp = {
                            domain = "example.com";
                            migrations = ./Application/Migration;
                            schema = ./Application/Schema.sql;
                            fixtures = ./Application/Fixtures.sql;
                            # sessionSecret = "CHANGE-ME";
                            # Uncomment to use a custom database URL
                            # databaseUrl = lib.mkForce "postgresql://postgres:...CHANGE-ME";
                        };
                    })
                ];
            };

        };
}
