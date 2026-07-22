# Travel Journal

A mixed-format site. The journal entry is Markdown with JSON frontmatter, while
the about page is a whole-file JSON object. The app supplies the frontmatter
parser and combines pure and effectful page decoders with record-builder syntax.

```sh
roc build main.roc --output=travel-journal
./travel-journal content output
```

On Windows PowerShell:

```powershell
roc build main.roc --output=travel-journal.exe
.\travel-journal.exe .\content .\output
```

The `frontmatter` helper accepts any compatible text parser, so a YAML package
can replace `Json.parse` without changing the platform.
