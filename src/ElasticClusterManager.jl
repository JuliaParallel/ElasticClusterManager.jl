module ElasticClusterManager

# We don't do `using Foo`
# We either do `using Foo: bar`, or we do `import Foo`
# https://github.com/JuliaLang/julia/pull/42080

import Distributed
import Sockets
import Pkg

# Bring some names into scope, just for convenience:
using Distributed: launch, manage, kill, init_worker, connect

export launch, manage, kill, init_worker, connect
export ElasticManager, elastic_worker

function worker_cookie()
  Distributed.init_multi()
  return Distributed.cluster_cookie()
end

worker_arg() = `--worker=$(worker_cookie())`

include("elastic.jl")

end
