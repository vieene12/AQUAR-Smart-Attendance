# Backend API configuration

Flutter reads the ASP.NET Core base URL exclusively from the compile-time
`API_BASE_URL` dart define. No localhost or production URL is embedded in the
application source.

PowerShell example:

```powershell
flutter run --dart-define=API_BASE_URL=https://your-api.example.com
```

Android Emulator example when a development backend is reachable through the
host alias:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Use HTTPS outside an isolated local development environment. The value must
include `http://` or `https://` and must not include query parameters or a URL
fragment. Missing or invalid configuration is shown as an application error;
account repositories never fall back to direct Firebase writes.
