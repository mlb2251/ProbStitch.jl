# ProbStitch.jl


```
julia> using Revise, ProbStitch
julia> PS.compress("data/cogsci/nuts-bolts.json")
StitchResult(ratio=1.78x, before_size=19008, rewritten_size=10688)
  1.78x [matches=320 arity=2 logposterior=9.026417533815254: (T (repeat (T l (M 1 0 -0.5 (/ 0.5 (tan (/ pi #A))))) #A (M 1 (/ (* 2 pi) #A) 0 0)) (M #B 0 0 0))]
  SMCStats(steps=0, proposals=0, expansions=86990, time_smc=1.5, time_rewrite=0.0047, abstraction_cache=81.34% (N=86990))

julia> PS.compress("data/cogsci/dials.json")
StitchResult(ratio=1.27x, before_size=35712, rewritten_size=28208)
  1.27x [matches=536 arity=4 logposterior=8.92319149068606: (T (T (T l (M 1 0 -0.5 0)) (M #A #B 0 0)) (M 1 0 #C #D))]
  SMCStats(steps=0, proposals=0, expansions=104971, time_smc=3.3, time_rewrite=0.013, abstraction_cache=80.2% (N=104971))

julia> PS.compress("data/cogsci/wheels.json")
StitchResult(ratio=1.34x, before_size=35426, rewritten_size=26354)
  1.34x [matches=1296 arity=5 logposterior=9.112948025967533: (T (T #A (M #B 0 0 #C)) (M 1 0 #D #E))]
  SMCStats(steps=0, proposals=0, expansions=56994, time_smc=1.4, time_rewrite=0.01, abstraction_cache=83.63% (N=56994))

julia> PS.compress("data/cogsci/furniture.json")
StitchResult(ratio=1.37x, before_size=42935, rewritten_size=31427)
  1.37x [matches=3836 arity=1 logposterior=9.35079772467144: (M 1 0 0 #A)]
  SMCStats(steps=0, proposals=0, expansions=149978, time_smc=26.0, time_rewrite=0.018, abstraction_cache=40.57% (N=149978))

```



