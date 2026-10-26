# ui

## Setup

```sh
flutter pub get
dart run husky install
```

## Development

Theme and palette are read from `%APPDATA%\Nyaxis\ui\theme.json` and `palette.json` on startup; missing keys are written back with their defaults.
