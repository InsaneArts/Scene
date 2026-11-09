# Security

## Reporting a vulnerability

Report it privately on GitHub: open the repository's Security tab and choose Report a vulnerability. Please don't open a public issue for it.

We answer within a few days, and we tell you when a fix ships.

## What is in scope

- Scene.app and its `scene-tweak` helper, in the latest release.
- `install.sh`.
- Anything a theme can reach: theme files, themes installed from GitHub, and the config files Scene writes from them. Themes are data, so a theme that makes Scene run code or write outside its own files is a vulnerability.
- The scripts you list in Settings → Scripts, where Scene runs them.

Scene changes only what its Apply sheet lists, and can put the original setup back. A change outside that list is a bug we want to hear about, too.
