platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [InternalTypes]
    provides [mainForHost]

Types : {
    a: InternalTypes.UrlPath,
    b: InternalTypes.Args,
}

mainForHost : Types
mainForHost = main
    