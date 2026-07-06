import path.Path as PathPkg

## Filesystem paths backed by the shared roc-lang/path package.
Path := [].{

	## Filesystem path type from roc-lang/path.
	Path : PathPkg.Path

	## Raw OS-specific path representation used at platform boundaries.
	Raw : [UnixBytes(List(U8)), WindowsU16s(List(U16))]

	## Create a Unix path from a Roc string by storing its UTF-8 bytes.
	unix : Str -> PathPkg.Path
	unix = PathPkg.unix

	## Create a Unix path from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> PathPkg.Path
	unix_bytes = PathPkg.unix_bytes

	## Create a Windows path from a Roc string by storing its UTF-16 code units.
	windows : Str -> PathPkg.Path
	windows = PathPkg.windows

	## Create a Windows path from raw UTF-16 code units.
	windows_u16s : List(U16) -> PathPkg.Path
	windows_u16s = PathPkg.windows_u16s

	## Convert a path to a string if its raw representation is valid text.
	to_str : PathPkg.Path -> Try(Str, [InvalidStr(U64)])
	to_str = PathPkg.to_str

	## Convert a path to a display string, replacing invalid text with U+FFFD.
	display : PathPkg.Path -> Str
	display = PathPkg.display

	## Returns everything after the last directory separator.
	filename : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
	filename = PathPkg.filename

	## Returns the filename extension without the leading dot.
	ext : PathPkg.Path -> Try(PathPkg.Path, [IsDirPath, EndsInDots])
	ext = PathPkg.ext

	## Adds a separator and a string component to the path.
	join : PathPkg.Path, Str -> PathPkg.Path
	join = PathPkg.join

	## Expose the raw OS-specific representation.
	to_raw : PathPkg.Path -> Raw
	to_raw = PathPkg.to_raw

	## Build a path from the raw OS-specific representation.
	from_raw : Raw -> PathPkg.Path
	from_raw = PathPkg.from_raw
}
