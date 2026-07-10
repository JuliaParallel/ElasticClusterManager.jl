@testset "ElasticManager" begin
    TIMEOUT = 60.

    em = ElasticManager(; addr=:auto, port=0)
    @test em isa ElasticManager

    # launch worker
    exeflags = ("--code-coverage=user", "--startup-file=no")
    connect_cmd = ElasticClusterManager.get_connect_cmd(em; exeflags=exeflags)
    run(`sh -c $connect_cmd`; wait=false)

    # wait at most TIMEOUT seconds for it to connect
    @test :ok == timedwait(TIMEOUT) do
        length(em.active) == 1
    end

    wait(rmprocs(workers()))

    @testset "show(io, ::ElasticManager)" begin
        str = sprint(show, em)
        lines = strip.(split(strip(str), '\n'))
        @test lines[1] == "ElasticManager:"
        @test lines[2] == "Active workers : []"
        @test lines[3] == "Number of workers to be added  : 0"
        @test lines[4] == "Terminated workers : [ 2]"
    end

    @testset "Other constructors for ElasticManager()" begin
        @test ElasticManager(9001) isa ElasticManager
        @test ElasticManager(ip"127.0.0.1", 9002) isa ElasticManager
        @test Distributed.HDR_COOKIE_LEN isa Real
        @test Distributed.HDR_COOKIE_LEN >= 16
        @test ElasticManager(ip"127.0.0.1", 9003, Random.randstring(Distributed.HDR_COOKIE_LEN)) isa ElasticManager
    end
end
