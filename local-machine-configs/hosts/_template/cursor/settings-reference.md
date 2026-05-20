# Cursor Settings Reference

This file documents the expected structure of Cursor IDE settings that can be versioned.

## Settings Location

- Windows: `%APPDATA%\Cursor\User\settings.json`
- macOS: `~/Library/Application Support/Cursor/User/settings.json`

## Common Settings to Version

### AI Rules
```json
{
  "cursor.rules": [
    {
      "name": "Project Rules",
      "filePath": ".cursor/rules"
    }
  ]
}
```

### Editor Settings
```json
{
  "editor.fontSize": 14,
  "editor.tabSize": 2,
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode"
}
```

## Notes

Only include settings that should be shared across machines. Machine-specific paths
(such as absolute file paths) should NOT be committed.
