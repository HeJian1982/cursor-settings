# Cursor Settings

This file documents expected Cursor IDE settings for the hj1982.cn project.

## Settings File Location

- Windows: `%APPDATA%\Cursor\User\settings.json`

## Recommended Settings

```json
{
  // AI Rules
  "cursor.rules": [
    {
      "name": "何健个人网站规则",
      "filePath": "e:\\HJ\\Web\\.cursor\\rules"
    }
  ],

  // Editor
  "editor.fontSize": 14,
  "editor.tabSize": 2,
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",

  // TypeScript
  "typescript.preferences.importModuleSpecifier": "non-relative",
  "javascript.preferences.importModuleSpecifier": "non-relative",

  // Tailwind
  "tailwindCSS.includeLanguages": {
    "typescriptreact": "html"
  },

  // Files
  "files.exclude": {
    "**/.git": true,
    "**/node_modules": true,
    "**/.next": true
  }
}
```

## How to Apply

1. Open Cursor Settings (Ctrl+, or Cmd+,)
2. Copy relevant settings from this file
3. Paste into settings.json
4. Save and reload
