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
                    ihp.nixosModules.app
                    ({ config, ihp, lib, pkgs, ... }: {
                        garnix.server.enable = true;
                        networking.firewall = {
                            enable = true;
                            allowedTCPPorts = [ 22 80 443 ];
                        };

                        security.acme.defaults.email = "letsencrypt@digitallyinduced.com";
                        security.acme.acceptTerms = true;

                        services.nginx = {
                            enable = true;
                            enableReload = true;
                            recommendedProxySettings = true;
                            recommendedGzipSettings = true;
                            recommendedOptimisation = true;
                            recommendedTlsSettings = true;
                            virtualHosts.default = {
                                default = true;
                                locations."/" = {
                                    proxyPass = "http://localhost:8000";
                                    proxyWebsockets = true;
                                };
                            };
                        };

                        systemd.services.worker.enable = lib.mkForce false;

                        environment.systemPackages = with pkgs; [ vim ];
                        programs.vim.enable = true;

                        services.ihp = {
                            domain = "example.com";
                            migrations = ./Application/Migration;
                            schema = ./Application/Schema.sql;
                            fixtures = ./Application/Fixtures.sql;
                            sessionSecret = "1J8jtRW331a0IbHBCHmsFNoesQUNFnuHqY8cB5927KsoV5sYmiq3DMmvsYk5S7EDma9YhqZLZWeTFu2pGOxMT2F/5PnifW/5ffwJjZvZcJh9MKPh3Ez9fmPEyxZBDxVp";
                            # Uncomment to use a custom database URL
                            # databaseUrl = lib.mkForce "postgresql://postgres:...CHANGE-ME";
                        };

                        # Postgres
                        services.postgresql = {
                            enable = true;
                            initialScript = let
                                cfg = config.services.ihp;
                                in pkgs.writeText "ihp-initScript" ''
                                    CREATE USER ${cfg.databaseUser};
                                    CREATE DATABASE ${cfg.databaseName} OWNER ${cfg.databaseUser};
                                    GRANT ALL PRIVILEGES ON DATABASE ${cfg.databaseName} TO "${cfg.databaseUser}";
                                    \connect ${cfg.databaseName}
                                    SET ROLE '${cfg.databaseUser}';
                                    CREATE TABLE IF NOT EXISTS schema_migrations (revision BIGINT NOT NULL UNIQUE);
                                    \i ${ihp}/lib/IHP/IHPSchema.sql
                                    \i ${cfg.schema}
                                    \i ${cfg.fixtures}
                                '';
                        };

                        services.ihp.databaseUser = "root";
                        services.ihp.databaseUrl = let cfg = config.services.ihp; in "postgresql://${cfg.databaseUser}@/${cfg.databaseName}";

                        environment.variables = let cfg = config.services.ihp; in {
                            PGUSER = cfg.databaseUser;
                            PGDATABASE = cfg.databaseName;
                        };

                    })
                ];
            };

        };
}
