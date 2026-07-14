# Legacy iOS Client

This folder contains the native iOS client skeleton.

Target:

- iOS 6.1.3 first.
- Jailbreak installation.
- Theos build system.
- Objective-C/UIKit.

The client intentionally talks only to the VibeSlopik bridge. It does not talk
to OpenAI, Codex Cloud, or a tunnel provider directly.

## Planned Build

```sh
cd ios/LegacyRemote
make package
```

The output is a jailbreak `.deb` under `packages/`. This is the preferred
install format for iFile/Filza/dpkg workflows.
