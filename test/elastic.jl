@testset "ElasticManager" begin
    TIMEOUT = 60.

    manage_events = Tuple{Int,Symbol}[]
    manage_callback(mgr, id, op) = push!(manage_events, (Int(id), op))

    em = ElasticManager(; addr=:auto, port=0, manage_callback=manage_callback)
    @test em isa ElasticManager

    # launch worker
    worker_cmd = ElasticClusterManager.worker_start_command(em; exeflags=`--code-coverage=user --startup-file=no`)
    run(worker_cmd; wait=false)

    # wait at most TIMEOUT seconds for it to connect
    @test :ok == timedwait(TIMEOUT) do
        length(em.active) == 1 && !isempty(manage_events)
    end

    wid = first(workers())
    @test manage_events == [(wid, :register)]
    @test remotecall_fetch(() -> 7 * 6, wid) == 42

    @testset "show with active worker" begin
        lines = strip.(split(strip(sprint(show, em)), '\n'))
        @test lines[2] == "Active workers : [ $wid]"
    end

    wait(rmprocs(workers()))

    @test :ok == timedwait(TIMEOUT) do
        length(manage_events) == 2
    end
    @test manage_events == [(wid, :register), (wid, :deregister)]
    @test wid in em.terminated

    @test ElasticClusterManager.elastic_no_op_callback(em, wid, :register) === nothing

    @testset "show(io, ::ElasticManager)" begin
        str = sprint(show, em)
        lines = strip.(split(strip(str), '\n'))
        @test lines[1] == "ElasticManager:"
        @test lines[2] == "Active workers : []"
        @test lines[3] == "Number of workers to be added  : 0"
        @test lines[4] == "Terminated workers : [ $wid]"
    end

    @testset "cookie validation" begin
        addr, port = em.sockname
        good_cookie = Distributed.cluster_cookie()

        # A connection with a wrong cookie must get closed:
        bad_cookie = (good_cookie[1] == 'x' ? "y" : "x") * good_cookie[2:end]
        sock = Sockets.connect(addr, port)
        write(sock, bad_cookie)
        @test isempty(read(sock))

        # A connection closed before sending a full cookie must not disturb
        # the manager:
        sock = Sockets.connect(addr, port)
        write(sock, good_cookie[1:3])
        close(sock)

        @test isempty(em.active)
    end

    @testset "elastic_worker env and forward_stdout" begin
        addr, port = em.sockname
        cookie = Distributed.cluster_cookie()
        code = "import ElasticClusterManager; " *
            "ElasticClusterManager.elastic_worker(\"$cookie\", \"$addr\", $(Int(port)); " *
            "env=[\"ELASTIC_TEST_VAR\" => \"42\"], forward_stdout=false)"
        worker_cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
        run(worker_cmd; wait=false)

        @test :ok == timedwait(TIMEOUT) do
            length(em.active) == 1
        end

        wid = first(workers())
        @test remotecall_fetch(() -> ENV["ELASTIC_TEST_VAR"], wid) == "42"

        wait(rmprocs(workers()))
    end

    @testset "worker_start_command" begin
        cmd = ElasticClusterManager.worker_start_command(em)
        @test cmd isa Cmd
        @test cmd.exec[1] == joinpath(Sys.BINDIR, Base.julia_exename())
        @test any(startswith.(cmd.exec, "--project="))
        @test cmd.exec[end-1] == "-e"
        @test occursin("elastic_worker(\"$(Distributed.cluster_cookie())\",\"$(em.sockname[1])\",$(Int(em.sockname[2])))", cmd.exec[end])

        cmd = ElasticClusterManager.worker_start_command(em; absolute_exename=false, same_project=false, exeflags=`--threads=2`)
        @test cmd.exec[1] == "julia"
        @test "--threads=2" in cmd.exec
        @test !any(startswith.(cmd.exec, "--project="))
    end

    @testset "get_connect_cmd" begin
        cmd = ElasticClusterManager.get_connect_cmd(em)
        @test occursin(joinpath(Sys.BINDIR, Base.julia_exename()), cmd)
        @test occursin("--project=", cmd)
        @test occursin(Distributed.cluster_cookie(), cmd)
        @test occursin(string(Int(em.sockname[2])), cmd)
        @test occursin("-e 'import ElasticClusterManager", cmd)

        cmd = ElasticClusterManager.get_connect_cmd(em; absolute_exename=false, same_project=false, exeflags=("--threads=2",))
        @test startswith(cmd, "julia ")
        @test occursin("--threads=2", cmd)
        @test !occursin("--project", cmd)
    end

    @testset "close" begin
        em2 = ElasticManager(; port=0)
        run(ElasticClusterManager.worker_start_command(em2; exeflags=`--code-coverage=user --startup-file=no`); wait=false)
        @test :ok == timedwait(TIMEOUT) do
            length(em2.active) == 1
        end
        @test isopen(em2)

        @test close(em2) === nothing

        @test !isopen(em2)
        @test :ok == timedwait(TIMEOUT) do
            isempty(em2.active)
        end
        @test workers() == [1]
        @test_throws Base.IOError Sockets.connect(em2.sockname...)
        @test close(em2) === nothing
    end

    @testset "Other constructors for ElasticManager()" begin
        em_dep1 = ElasticManager(9001)
        @test em_dep1 isa ElasticManager
        em_dep2 = ElasticManager(ip"127.0.0.1", 9002)
        @test em_dep2 isa ElasticManager
        @test Distributed.HDR_COOKIE_LEN isa Real
        @test Distributed.HDR_COOKIE_LEN >= 16
        em_dep3 = ElasticManager(ip"127.0.0.1", 9003, Random.randstring(Distributed.HDR_COOKIE_LEN))
        @test em_dep3 isa ElasticManager
        foreach(close, (em_dep1, em_dep2, em_dep3))
    end

    close(em)
    @test !isopen(em)
end
