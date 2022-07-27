using Test, Sockets, LanguageServer, CSTParser, SymbolServer, SymbolServer.Pkg, StaticLint, LanguageServer.JSON, LanguageServer.JSONRPC
using LanguageServer: 
    Document,
    TextDocument,
    apply_text_edits,
    get_text_document,
    set_text_document!,
    get_text,
    get_offset,
    get_line_offsets,
    get_position_from_offset,
    get_open_in_editor,
    set_open_in_editor,
    is_workspace_file,
    get_uri
using LanguageServer.URIs2
const LS = LanguageServer
const Range = LanguageServer.Range

# TODO Replace this with a proper mock endpoint
JSONRPC.send(::Nothing, ::Any, ::Any) = nothing
function settestdoc(text)
    empty!(server._documents)
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:testdoc", "julia", 0, text)), server, nothing)

    doc = LanguageServer.getdocument(server, uri"untitled:testdoc")
    LanguageServer.parse_all(doc, server)
    doc
end

function on_all_docs(server, f)
    for doc in values(server._documents)
        f(doc)
    end
end

function on_all_offsets(doc, f)
    offset = 1
    while offset <= lastindex(get_text(doc))
        f(doc, offset)
        offset = nextind(get_text(doc), offset)
    end
end

@testset "LanguageServer" begin    
    @testset "document" begin
        include("test_document.jl")
    end
    @testset "communication" begin
        include("test_communication.jl")
    end
    @testset "intellisense" begin
        include("test_intellisense.jl")

        server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
        server.runlinter = true
        server.jr_endpoint = nothing
        LanguageServer.initialize_request(init_request, server, nothing)

        @testset "completions" begin
            include("requests/completions.jl")
        end
        @testset "actions" begin
            include("requests/actions.jl")
        end
        @testset "features" begin
            include("requests/features.jl")
        end
        @testset "hover" begin
            include("requests/hover.jl")
        end
        @testset "textdocument" begin
            include("requests/textdocument.jl")
        end
        @testset "misc" begin
            include("requests/misc.jl")
        end
        @testset "brute force tests" begin
            @info "Self-parse test"
            if get(ENV, "CI", false) != false
                @info "skipping brute-force tests on CI"
            else
                # run tests against each position in each document
                empty!(server._documents)
                LanguageServer.load_folder(dirname(String(first(methods(LanguageServer.eval)).file)), server)
                on_all_docs(server, doc -> begin
                    @info "Testing LS functionality at all offsets" file=get_uri(doc)
                    on_all_offsets(doc, function (doc, offset)
                        tdi = LanguageServer.TextDocumentIdentifier(get_uri(doc))
                        pos = LanguageServer.Position(LanguageServer.get_position_from_offset(doc, offset)...)
                        @test LanguageServer.get_offset(doc, LanguageServer.get_position_from_offset(doc, offset)...) == offset
                        LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(tdi, pos, missing), server, server.jr_endpoint)
                        LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                        LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                        LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                        LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(tdi, pos, missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)
                        LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(tdi, pos, missing, "newname"), server, server.jr_endpoint)
                    end)
                end)

                on_all_docs(server, doc -> begin
                    symbols=length(LanguageServer.textDocument_documentSymbol_request(LanguageServer.DocumentSymbolParams(LanguageServer.TextDocumentIdentifier(get_uri(doc)),missing, missing), server, server.jr_endpoint))
                    @info "Found $symbols symbols" file=get_uri(doc)
                end)

                LanguageServer.workspace_symbol_request(LanguageServer.WorkspaceSymbolParams("", missing, missing), server, server.jr_endpoint)
            end
        end
    end
    @testset "edit" begin
        include("test_edit.jl")
    end
    @testset "paths" begin
        include("test_paths.jl")
    end

    include("test_uris2.jl")
    include("test_juliaworkspace.jl")
    
    @testset "misc" begin
        include("test_misc.jl")
    end
end
