import path.Path as PathPkg
import OsStr exposing [OsStr]

## Filesystem paths backed by the shared roc-lang/path package.
Path := [].{

	## Filesystem path type from roc-lang/path.
	Path : PathPkg.Path

	## Raw OS-specific path representation used at platform boundaries.
	Raw : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

	## Create a path from an OS string without losing native path units.
	from_os_str : OsStr -> PathPkg.Path
	from_os_str = |os_str| PathPkg.from_raw(OsStr.to_raw(os_str))

	## Convert a path to an OS string without losing native path units.
	to_os_str : PathPkg.Path -> OsStr
	to_os_str = |path| OsStr.from_raw(PathPkg.to_raw(path))

	## Create a portable UTF-8 text path.
	utf8 : Str -> PathPkg.Path
	utf8 = |str| PathPkg.utf8(str)

	## Create a portable UTF-8 path from a quoted literal.
	from_quote : Str -> Try(PathPkg.Path, [BadQuotedBytes(Str)])
	from_quote = |str| PathPkg.from_quote(str)

	## Create a Unix path from a Roc string by storing its UTF-8 bytes.
	unix : Str -> PathPkg.Path
	unix = |str| PathPkg.unix(str)

	## Create a Unix path from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> PathPkg.Path
	unix_bytes = |bytes| PathPkg.unix_bytes(bytes)

	## Create a Windows path from a Roc string by storing its UTF-16 code units.
	windows : Str -> PathPkg.Path
	windows = |str| PathPkg.windows(str)

	## Create a Windows path from raw UTF-16 code units.
	windows_u16s : List(U16) -> PathPkg.Path
	windows_u16s = |u16s| PathPkg.windows_u16s(u16s)

	## Convert a path to a string if its raw representation is valid text.
	to_str : PathPkg.Path -> Try(Str, [InvalidStr(U64)])
	to_str = |path| PathPkg.to_str(path)

	## Convert a path to a display string, replacing invalid text with U+FFFD.
	display : PathPkg.Path -> Str
	display = |path| PathPkg.display(path)

	## Returns everything after the last directory separator.
	filename : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
	filename = |path| PathPkg.filename(path)

	## Returns the filename extension without the leading dot.
	ext : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
	ext = |path| PathPkg.ext(path)

	## Adds a separator and a string component to the path.
	join : PathPkg.Path, Str -> PathPkg.Path
	join = |path, component| PathPkg.join(path, component)

	## Expose the raw OS-specific representation.
	to_raw : PathPkg.Path -> Raw
	to_raw = |path| PathPkg.to_raw(path)

	## Build a path from the raw OS-specific representation.
	from_raw : Raw -> PathPkg.Path
	from_raw = |raw| PathPkg.from_raw(raw)
}

## Converting an OS string to a path preserves Windows UTF-16 code units.
expect Path.to_raw(Path.from_os_str(OsStr.windows_u16s([0xD83D, 0xDC36]))) == WindowsU16s([0xD83D, 0xDC36])

## Converting a path back to an OS string also preserves unpaired surrogates.
expect OsStr.to_raw(Path.to_os_str(Path.windows_u16s([0xD800, 97]))) == WindowsU16s([0xD800, 97])
