# QR code generator

Vendored from [Greaby/godot-qrcode-generator](https://github.com/Greaby/godot-qrcode-generator),
licensed under MIT. Only the three runtime classes are included. Local changes:

- dependencies use explicit `preload` paths instead of global class registration;
- generated images use the QR-standard four-module quiet zone.

See `LICENSE` in this directory for the upstream license text.
