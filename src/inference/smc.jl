export smc

Base.@kwdef struct Config
    num_particles::Int=3000
    seed::Union{Int,Nothing}=nothing
    verbose_best::Bool=false
    prefix::String="fn_"
    N::Int=1
    max_steps::Int=50
    temperature::Float64=1.0
    utility_fn::Function=utility_by_rewrite
    logprob_mode::Bool=false
    record_json::Bool=false
end

mutable struct SMCStats
    steps::Int
    proposals::Int
    expansions::Int
    time_smc::Float64
    time_rewrite::Float64
    abstraction_cache::HitRate
end
SMCStats() = SMCStats(0, 0, 0, 0., 0., HitRate())

# mutable struct Shared
#     abstraction_cache::Dict{PExpr, Abstraction}
#     stats::SMCStats
# end
# Shared() = Shared(Dict{PExpr, Abstraction}(), SMCStats())


mutable struct SMCFrame
    particles::Vector{Abstraction}
    logtotals_before_resampling::Vector{Float64}
    logtotals_after_resampling::Vector{Float64}
    counts_before_resampling::Vector{Int}
    counts_after_resampling::Vector{Int}
    ancestors::Vector{Int}
end

function SMCFrame(config::Config)
    SMCFrame(empty!(Vector{Abstraction}(undef, config.num_particles)),
             empty!(Vector{Float64}(undef, config.num_particles)),
             empty!(Vector{Float64}(undef, config.num_particles)),
             empty!(Vector{Int}(undef, config.num_particles)),
             empty!(Vector{Int}(undef, config.num_particles)),
             empty!(Vector{Int}(undef, config.num_particles)))
end

function sort_frame!(frame::SMCFrame)
    perm = sortperm(frame.logtotals_after_resampling, rev=true)
    frame.particles .= frame.particles[perm]
    frame.logtotals_before_resampling .= frame.logtotals_before_resampling[perm]
    frame.logtotals_after_resampling .= frame.logtotals_after_resampling[perm]
    frame.counts_before_resampling .= frame.counts_before_resampling[perm]
    frame.counts_after_resampling .= frame.counts_after_resampling[perm]
end

function dead_particle(abs::Abstraction)
    isempty(abs.metavar_paths   )
end

function dead_frame(frame::SMCFrame)
    all(dead_particle, frame.particles)
end

function push_particle!(frame::SMCFrame, abs::Abstraction, logweight::Float64, ancestor::Int)
    push!(frame.particles, abs)
    push!(frame.logtotals_before_resampling, logweight)
    push!(frame.logtotals_after_resampling, logweight)
    push!(frame.counts_before_resampling, 1)
    push!(frame.counts_after_resampling, 0)
    push!(frame.ancestors, ancestor)
    frame
end

function add_to_particle!(frame::SMCFrame, idx::Int, logweight::Float64)
    frame.logtotals_before_resampling[idx] = logaddexp(frame.logtotals_before_resampling[idx], logweight)
    frame.counts_before_resampling[idx] += 1
    frame
end





mutable struct SMC
    frames::Vector{SMCFrame}
    config::Config
    stats::SMCStats
    abs_of_expr::Dict{PExpr, Abstraction}
    abs_of_id::Vector{Abstraction}
    step::Int
end

function SMC(config::Config)
    frames = SMCFrame[SMCFrame(config) for _ in 1:config.max_steps + 1]
    SMC(frames, config, SMCStats(), Dict{PExpr, Abstraction}(), Abstraction[], -1)
end

function get_frame(smc::SMC, step::Int)
    smc.frames[step+1]
end

function get_next_frame(smc::SMC)
    smc.step += 1
    frame = get_frame(smc, smc.step)
    frame
end





(Base.:+)(a::SMCStats, b::SMCStats) = SMCStats(a.steps + b.steps, a.proposals + b.proposals, a.expansions + b.expansions, a.time_smc + b.time_smc, a.time_rewrite + b.time_rewrite, a.abstraction_cache + b.abstraction_cache)

Base.show(io::IO, stats::SMCStats) = print(io, "SMCStats(steps=$(stats.steps), proposals=$(stats.proposals), expansions=$(stats.expansions), time_smc=$(round(stats.time_smc, sigdigits=2)), time_rewrite=$(round(stats.time_rewrite, sigdigits=2)), abstraction_cache=$(stats.abstraction_cache))")

struct SMCResult
    abstraction::Abstraction
    before::Corpus
    rewritten::Corpus
    stats::SMCStats
    logger
end


struct StitchResult
    before::Corpus
    rewritten::Corpus
    rounds::Vector{SMCResult}
    stats::SMCStats
end


function Base.show(io::IO, result::StitchResult)
    before_size = size(result.before)
    rewritten_size = size(result.rewritten)
    ratio = before_size / rewritten_size
    println(io, "StitchResult(ratio=$(round(ratio, digits=2))x, before_size=$before_size, rewritten_size=$rewritten_size)")
    for (i, round) in enumerate(result.rounds)
        println(io, "  ", round)
        # i < length(result.steps) && println(io)
    end
    print(io, "  ", result.stats)
end

function Base.show(io::IO, result::SMCResult)
    ratio = size(result.before) / size(result.rewritten)
    print(io, round(ratio, digits=2), "x ", result.abstraction)
end

function compress(path::String; kwargs...)
    compress(load_corpus(path); kwargs...)
end

function cogsci(; kwargs...)
    paths = [
        "data/cogsci/nuts-bolts.json",
        # "data/cogsci/bridge.json",
        "data/cogsci/dials.json",
        "data/cogsci/furniture.json",
        # "data/cogsci/house.json",
        "data/cogsci/wheels.json",
        # "data/cogsci/city.json",
        # "data/cogsci/castle.json",
    ]
    for path in paths
        println(path)
        @time result = compress(path; kwargs...)
        println(result)
    end
end




function compress(corpus::Corpus; kwargs...)
    config = Config(;kwargs...)
    before = corpus
    results = SMCResult[]
    for i in 1:config.N
        name = Symbol(config.prefix, i)
        result = smc(corpus, config, name)
        push!(results, result)
        corpus = result.rewritten
    end
    rewritten = isempty(results) ? before : results[end].rewritten
    res = StitchResult(before, rewritten, results, sum(result.stats for result in results))

    if config.record_json
        dir = timestamp_dir()
        write_out(res, dir, "result.json")
    end

    return res
end

function smc(corpus::Corpus, config::Config, name::Symbol)

    tstart = time()
    @assert !has_prim(corpus, name) "Primitive $(name) already exists in corpus"

    smc = SMC(config)
    next_frame = get_next_frame(smc)

    # start with a single particle
    init_abs = identity_abstraction(corpus, name)
    push_particle!(next_frame, init_abs, 0., 0)
    next_frame.counts_before_resampling[1] = config.num_particles
    next_frame.counts_after_resampling[1] = config.num_particles

    best_utility = 0.
    best_particle = init_abs

    !isnothing(config.seed) && Random.seed!(config.seed)
    # println("seed: ", Random.seed!())

    idx_of_abs_id = Dict{Int, Int}()


    while true
        smc.step + 1 > config.max_steps && break
        dead_frame(next_frame) && break

        prev_frame = next_frame
        next_frame = get_next_frame(smc)

        # smc.stats.steps += 1

        # SMC STEP
        for i in eachindex(prev_frame.particles)
            @inbounds abs = prev_frame.particles[i]
            dead_particle(abs) && continue
            @inbounds count = prev_frame.counts_after_resampling[i]

            # we need to empty this on a per-ancestor basis so that two particles
            # with different ancestors are not counted as the same particle
            empty!(idx_of_abs_id)

            for k in 1:count

                new_abs = sample_expansion(smc, abs)

                # check if posterior is already set via cache
                if isnan(new_abs.logposterior)
                    new_abs.logposterior = log(max(1., config.utility_fn(new_abs))) / config.temperature
                end

                logweight = dead_particle(new_abs) ? -Inf : new_abs.logposterior

                if haskey(idx_of_abs_id, new_abs.id)
                    # right now logweight will always be the same since we're not allowing
                    # one particle to come from different ancestors
                    idx = idx_of_abs_id[new_abs.id]
                    add_to_particle!(next_frame, idx, logweight)
                else 
                    push_particle!(next_frame, new_abs, logweight, i)
                    idx_of_abs_id[new_abs.id] = length(next_frame.particles)
                end

                if new_abs.logposterior > best_utility
                    best_utility = new_abs.logposterior
                    best_particle = new_abs
                    config.verbose_best && println("new best: ", new_abs)
                end

            end
        end

        dead_frame(next_frame) && break


        # RESAMPLE
        resample_residual!(next_frame.logtotals_before_resampling, next_frame.counts_after_resampling, config.num_particles)
        @assert sum(next_frame.counts_after_resampling) == config.num_particles

        # set logtotals_after_resampling to log(average weight times counts)
        log_avg_weight = logsumexp(next_frame.logtotals_before_resampling) .- log(config.num_particles)
        for i in eachindex(next_frame.particles)
            @inbounds next_frame.logtotals_after_resampling[i] = log_avg_weight + log(next_frame.counts_after_resampling[i])
        end

        # sort by logtotals_after_resampling
        sort_frame!(next_frame)
    end

    logger = JSONLogger(smc)
    config.record_json && log_all!(logger)

    smc.stats.time_smc = time() - tstart

    tstart = time()
    rewritten = rewrite(corpus, best_particle)
    smc.stats.time_rewrite = time() - tstart

    return SMCResult(best_particle, corpus, rewritten, smc.stats, logger)
end


using Profile, PProf
export ptime, pprofile, pallocs
function ptime(f)
    Base.GC.gc()
    @time f()
end
function pprofile(f)
    ptime(f) # warmstart
    Base.GC.gc()
    Profile.clear()
    @profile f()
    pprof()
end
function pallocs(f; sample_rate=.001)
    ptime(f) # warmstart
    Base.GC.gc()
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate=.001 f()
    PProf.Allocs.pprof()
end


