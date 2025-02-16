module ElasticClusterManager

using Distributed
using Sockets
import Pkg

export launch, manage, kill, init_worker, connect

export ElasticManager, elastic_worker

import Distributed: launch, manage, kill, init_worker, connect

function worker_cookie()
  Distributed.init_multi()
  return Distributed.cluster_cookie()
end

worker_arg() = `--worker=$(worker_cookie())`

include("elastic.jl")

end
