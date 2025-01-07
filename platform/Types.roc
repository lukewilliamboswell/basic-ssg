module [
    Args,
    Path,
    Files,
    RelPath,
    path_to_str,
    rel_path_to_str,
    to_rel_path,
]

Path := Str implements [Inspect]

path_to_str : Path -> Str
path_to_str = \@Path(str) -> str

RelPath := Str implements [Inspect]

rel_path_to_str : RelPath -> Str
rel_path_to_str = \@RelPath(str) -> str

to_rel_path : Str -> RelPath
to_rel_path = @RelPath

Args : {
    input_dir : Path,
    output_dir : Path,
}

Files : {
    url : Str,
    path : Path,
    relpath : RelPath,
}
