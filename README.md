# ElasticClusterManager.jl

The ElasticClusterManager.jl package implements the `ElasticManager`, a
cluster manager for dynamically adding and removing Julia workers.

This code originally lived in the [`ClusterManagers.jl`](https://github.com/JuliaParallel/ClusterManagers.jl) package.

## Using `ElasticManager` (dynamically adding workers to a cluster)

The `ElasticManager` is useful in scenarios where we want to dynamically add workers to a cluster.
It achieves this by listening on a known port on the master. The launched workers connect to this
port and publish their own host/port information for other workers to connect to.

On the master, you need to instantiate an instance of `ElasticManager`:

```julia
ElasticManager(;
    addr=IPv4("127.0.0.1"), port=9009, cookie=nothing,
    topology=:all_to_all, manage_callback=elastic_no_op_callback
)
```

You can set `addr=:auto` to automatically use the host's private IP address on the local network, which will allow other workers on this network to connect. You can also use `port=0` to let the OS choose a random free port for you (some systems may not support this), e.g.:

```julia
julia> em = ElasticManager(addr=:auto, port=0)
ElasticManager:
  Active workers : []
  Number of workers to be added  : 0
  Terminated workers : []
```

Workers are then started as separate Julia processes that call
`ElasticClusterManager.elastic_worker` to connect to the master.
Use `ElasticClusterManager.get_connect_cmd(em; kwargs...)` to generate a suitable system command to start up a
worker process, e.g.:

```julia
print(ElasticClusterManager.get_connect_cmd(em))
```

```
/home/user/bin/julia --project=/home/user/myproject/Project.toml -e 'import ElasticClusterManager; ElasticClusterManager.elastic_worker("4cOSyaYpgSl6BC0C","127.0.1.1",36275)'
```

By default, the generated command uses the absolute path of the current Julia executable and activates the same project as the current session; use the keyword arguments `absolute_exename=false` and `same_project=false` to change this.

Once workers have connected, `show(em)` will show them added to the list of active workers.
