platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [InternalTypes]
    provides [mainForHost]

Types : {
    a: InternalTypes.UrlPath,
}

mainForHost : Types
mainForHost = main
    