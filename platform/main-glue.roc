platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [Types]
    provides [mainForHost]

Types : {
    a: Types.Files,
    b: Types.Args,
    c: Types.Path, 
    d: Types.RelPath,
}

mainForHost : Types
mainForHost = main
    