using BenchmarkTools, TaylorModels

SUITE = BenchmarkGroup()

include("arithmetic.jl")
include("daisy/daisy.jl")
