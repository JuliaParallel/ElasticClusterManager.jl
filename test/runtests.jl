import ElasticClusterManager
import Test

import Distributed
import Random

# Bring some names into scope, just for convenience:
using Distributed: addprocs, rmprocs
using Distributed: workers, nworkers
using Distributed: procs, nprocs
using Distributed: remotecall_fetch, @spawnat
using Distributed: @ip_str
using Test: @testset, @test, @test_skip

# ElasticManager:
using ElasticClusterManager: ElasticManager

@testset "ElasticClusterManager.jl" begin
    include("elastic.jl")
end # @testset
