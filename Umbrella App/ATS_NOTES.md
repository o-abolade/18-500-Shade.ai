# App Transport Security (ATS) – Local HTTP

This app connects to a Raspberry Pi umbrella server over **local HTTP** (e.g. `http://192.168.1.100:8080`). By default, iOS blocks non-HTTPS connections.

## Configuration

`Info.plist` (project root) includes:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

`NSAllowsLocalNetworking` allows HTTP to local network devices (link-local and private IP ranges). This is the recommended approach for local IoT control.

## Notes

- Use this only for local development and home network control.
- Do **not** use `NSAllowsArbitraryLoads`; it disables ATS for all domains and is rejected by App Store review.
- For production apps that need internet access, use HTTPS and keep `NSAllowsLocalNetworking` only if local device control is required.
- Your Mac and iPhone must be on the same local network as the Raspberry Pi for connections to succeed.
