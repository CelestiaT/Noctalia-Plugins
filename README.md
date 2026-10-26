# Noctalia Plugins

Personal [Noctalia](https://github.com/noctalia-dev/noctalia) shell plugin
source. Add it once, then enable any plugin from the store or CLI.

> Noctalia plugins are trusted, unsandboxed Luau scripts running as you.
> Read every plugin's code and README before enabling — here, as anywhere.

## Install this source

```sh
noctalia msg plugins source add celestiat git https://github.com/CelestiaT/Noctalia-Plugins.git
# if a github.com -> mirror rewrite in your git config gets in the way:
noctalia msg plugins source add celestiat git git@github.com:CelestiaT/Noctalia-Plugins.git
```

Then enable a plugin, e.g.:

```sh
noctalia msg plugins enable celestiat/crosshair
```

## Plugins

| Plugin | Entry points | Requires | Description |
| --- | --- | --- | --- |
| [Crosshair](crosshair/README.md) | bar widget `toggle`, layer `overlay` | plugin API 36 (Noctalia nightly / >= 5.4) | Click-through fullscreen aiming crosshair on the overlay layer: color, outline, center/inner/outer line sets, and screen offset all configurable. |

## Layout

```
.
├── catalog.toml        # shell-facing index; keep version/updated_at in sync
└── <plugin>/           # one directory per plugin, named after the id suffix
    ├── plugin.toml
    ├── *.luau
    ├── README.md
    ├── thumbnail.webp  # 960x540 WebP
    └── translations/en.json
```

## Development

- `.luau` edits hot-reload for the enabled plugin; manifest changes apply on
  the next config reload or `noctalia msg plugins update celestiat`.
- After changing a plugin: bump `version` in `plugin.toml`, mirror it in
  `catalog.toml` (with a fresh `updated_at`), commit, push.
- Optional: fetch the official type stubs for luau-lsp autocomplete (gitignored):
  ```sh
  curl -O https://raw.githubusercontent.com/noctalia-dev/official-plugins/main/noctalia.d.luau
  ```

## License

The repository tooling and documentation are MIT licensed (see [LICENSE](LICENSE)).
Each plugin's license is declared in its own `plugin.toml`; `crosshair` is MIT.
