"""
Two serializers of one resolved representation. Neither infers anything. See
`src/Render/README.md`.
"""
module Render

using DBInterface
using SQLite
using Unicode

using ..Source: RawSpan, anchor_id
using ..Adjudication
using ..Resolve

include("tei.jl")
include("sqlite.jl")

export render_tei, render_sqlite

end
