# The master process listens on a well-known port
# Launched workers connect to the master and redirect their STDOUTs to the same
# Workers can join and leave the cluster on demand.

const HDR_COOKIE_LEN = Distributed.HDR_COOKIE_LEN

@static if Base.VERSION >= v"1.7-"
    # Base.errormonitor() is only available in Julia 1.7+
    my_errormonitor(t) = Base.errormonitor(t)
else
    my_errormonitor(t) = nothing
end

struct ElasticManager <: Distributed.ClusterManager
    active::Dict{Int, Distributed.WorkerConfig}        # active workers
    pending::Channel{Sockets.TCPSocket}          # to be added workers
    terminated::Set{Int}             # terminated worker ids
    topology::Symbol
    sockname
    printing_kwargs

    function ElasticManager(;addr=Sockets.IPv4("127.0.0.1"), port=9009, cookie=nothing, topology=:all_to_all, printing_kwargs=())
        Distributed.init_multi()
        cookie !== nothing && Distributed.cluster_cookie(cookie)

        # Automatically check for the IP address of the local machine
        if addr == :auto
            try
                addr = Sockets.getipaddr(Distributed.IPv4)
            catch
                error("Failed to automatically get host's IP address. Please specify `addr=` explicitly.")
            end
        end

        l_sock = Distributed.listen(addr, port)

        lman = new(Dict{Int, Distributed.WorkerConfig}(), Channel{Sockets.TCPSocket}(typemax(Int)), Set{Int}(), topology, Sockets.getsockname(l_sock), printing_kwargs)

        t1 = @async begin
            while true
                let s = Sockets.accept(l_sock)
                    t2 = @async process_worker_conn(lman, s)
                    my_errormonitor(t2)
                end
            end
        end
        my_errormonitor(t1)

        t3 = @async process_pending_connections(lman)
        my_errormonitor(t3)

        lman
    end
end

ElasticManager(port) = ElasticManager(;port=port)
ElasticManager(addr, port) = ElasticManager(;addr=addr, port=port)
ElasticManager(addr, port, cookie) = ElasticManager(;addr=addr, port=port, cookie=cookie)


function process_worker_conn(mgr::ElasticManager, s::Sockets.TCPSocket)
    # Socket is the worker's STDOUT
    wc = Distributed.WorkerConfig()
    wc.io = s

    # Validate cookie
    cookie = read(s, HDR_COOKIE_LEN)
    if length(cookie) < HDR_COOKIE_LEN
        error("Cookie read failed. Connection closed by peer.")
    end
    self_cookie = Distributed.cluster_cookie()
    for i in 1:HDR_COOKIE_LEN
        if UInt8(self_cookie[i]) != cookie[i]
            println(i, " ", self_cookie[i], " ", cookie[i])
            error("Invalid cookie sent by remote worker.")
        end
    end

    put!(mgr.pending, s)
end

function process_pending_connections(mgr::ElasticManager)
    while true
        wait(mgr.pending)
        try
            Distributed.addprocs(mgr; topology=mgr.topology)
        catch e
            showerror(stderr, e)
            Base.show_backtrace(stderr, Base.catch_backtrace())
        end
    end
end

function Distributed.launch(mgr::ElasticManager, params::Dict, launched::Array, c::Condition)
    # The workers have already been started.
    while isready(mgr.pending)
        wc=Distributed.WorkerConfig()
        wc.io = take!(mgr.pending)
        push!(launched, wc)
    end

    notify(c)
end

function Distributed.manage(mgr::ElasticManager, id::Integer, config::Distributed.WorkerConfig, op::Symbol)
    if op == :register
        mgr.active[id] = config
    elseif  op == :deregister
        delete!(mgr.active, id)
        push!(mgr.terminated, id)
    end
end

function Base.show(io::IO, mgr::ElasticManager)
    iob = IOBuffer()

    println(iob, "ElasticManager:")
    print(iob, "  Active workers : [ ")
    for id in sort(collect(keys(mgr.active)))
        print(iob, id, ",")
    end
    seek(iob, position(iob)-1)
    println(iob, "]")

    println(iob, "  Number of workers to be added  : ", Base.n_avail(mgr.pending))

    print(iob, "  Terminated workers : [ ")
    for id in sort(collect(mgr.terminated))
        print(iob, id, ",")
    end
    seek(iob, position(iob)-1)
    println(iob, "]")

    println(iob, "  Worker connect command : ")
    print(iob, "    ", get_connect_cmd(mgr; mgr.printing_kwargs...))

    print(io, String(take!(iob)))
end

# Does not return. If executing from a REPL try
# @async connect_to_cluster(.....)
# addr, port that a ElasticManager on the master processes is listening on.
function elastic_worker(cookie, addr="127.0.0.1", port=9009; stdout_to_master=true)
    c = connect(addr, port)
    write(c, rpad(cookie, HDR_COOKIE_LEN)[1:HDR_COOKIE_LEN])
    stdout_to_master && redirect_stdout(c)
    Distributed.start_worker(c, cookie)
end

function get_connect_cmd(em::ElasticManager; absolute_exename=true, same_project=true, exeflags::Tuple=())
    ip = string(em.sockname[1])
    port = convert(Int,em.sockname[2])
    cookie = Distributed.cluster_cookie()
    exename = absolute_exename ? joinpath(Sys.BINDIR, Base.julia_exename()) : "julia"
    project = same_project ? ("--project=$(Pkg.API.Context().env.project_file)",) : ()

    join([
        exename,
        exeflags...,
        project...,
        "-e 'import ElasticClusterManager; ElasticClusterManager.elastic_worker(\"$cookie\",\"$ip\",$port)'"
    ]," ")

end
