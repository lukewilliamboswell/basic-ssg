# Article Inspector

A small content utility that renders one Markdown file and prints its first
heading, falling back to `Untitled` when no heading is present. It demonstrates
mapping platform failures into an application-specific error.

```sh
roc build main.roc --output=article-inspector
./article-inspector sample/welcome.md
```

On Windows PowerShell:

```powershell
roc build main.roc --output=article-inspector.exe
.\article-inspector.exe .\sample\welcome.md
```
