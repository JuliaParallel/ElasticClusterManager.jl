# ElasticClusterManager.jl

The ElasticClusterManager.jl package implements the `ElasticManager`.

This code originally lived in the [`ClusterManagers.jl`](https://github.com/JuliaParallel/ClusterManagers.jl) package.

The following managers are implemented in this package:

| Manager | Command to add processors |
| ---------------- | ------------------------- |
| ElasticManager | `addprocs(ElasticManager(...)` |


## Using `ElasticManager` (dynamically adding workers to a cluster)

The `ElasticManager` is useful in scenarios where we want to dynamically add workers to a cluster.
It achieves this by listening on a known port on the master. The launched workers connect to this
port and publish their own host/port information for other workers to connect to.

On the master, you need to instantiate an instance of `ElasticManager`. The constructors defined are:

```julia
ElasticManager(;addr=IPv4("127.0.0.1"), port=9009, cookie=nothing, topology=:all_to_all, printing_kwargs=())
ElasticManager(port) = ElasticManager(;port=port)
ElasticManager(addr, port) = ElasticManager(;addr=addr, port=port)
ElasticManager(addr, port, cookie) = ElasticManager(;addr=addr, port=port, cookie=cookie)
```

You can set `addr=:auto` to automatically use the host's private IP address on the local network, which will allow other workers on this network to connect. You can also use `port=0` to let the OS choose a random free port for you (some systems may not support this). Once created, printing the `ElasticManager` object prints the command which you can run on workers to connect them to the master, e.g.:

```julia
julia> em = ElasticManager(addr=:auto, port=0)
ElasticManager:
  Active workers : []
  Number of workers to be added  : 0
  Terminated workers : []
  Worker connect command :
    /home/user/bin/julia --project=/home/user/myproject/Project.toml -e 'using ClusterManagers; ClusterManagers.elastic_worker("4cOSyaYpgSl6BC0C","127.0.1.1",36275)'
```

By default, the printed command uses the absolute path to the current Julia executable and activates the same project as the current session. You can change either of these defaults by passing `printing_kwargs=(absolute_exename=false, same_project=false))` to the first form of the `ElasticManager` constructor.

Once workers are connected, you can print the `em` object again to see them added to the list of active workers.
