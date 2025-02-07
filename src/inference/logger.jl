

const PARTICLE_FIELDNAMES = ["abs_id", "logweight"]
const ABS_FIELDNAMES = ["expr", "num_matches", "size", "logposterior"]

mutable struct JSONLogger
    state::SMC
    history::Vector{Any}
    idx_of_abs::Dict{PExpr, Int}
    logged_abstractions::Vector{Any}
end

function JSON.lower(logger::JSONLogger)
    return Dict(
        :config => logger.state.config,
        :history => logger.history,
        :logged_abstractions => logger.logged_abstractions,
        :PARTICLE_FIELDNAMES => PARTICLE_FIELDNAMES,
        :ABS_FIELDNAMES => ABS_FIELDNAMES,
    )
end


function JSONLogger(smc::SMC)
    return JSONLogger(smc, [], Dict{PExpr, Int}(), [])
end

function log_all!(logger::JSONLogger)
    for i in 0:logger.state.step
        log_frame!(logger, i)
    end
    logger
end

function log_frame!(logger::JSONLogger, step::Int)
    frame = get_frame(logger.state, step)
    history_frame = Dict(
        :step => step,
        :particles => [log!(logger, particle) for particle in frame.particles],
        :logtotals_before_resampling => round3.(frame.logtotals_before_resampling),
        :logtotals_after_resampling => round3.(frame.logtotals_after_resampling),
        :counts_before_resampling => frame.counts_before_resampling,
        :counts_after_resampling => frame.counts_after_resampling,
        :ancestors => frame.ancestors,
    )
    push!(logger.history, history_frame)
    logger
end




function log!(logger::JSONLogger, step::Int)
    state = logger.state
    history_frame = Dict(
        :step => step,
        :ancestors => copy(state.ancestors),
        :particles => [
            Any[
                log!(logger, state.particles[i].abs), # abs_id
                round3(state.logweights[i]), # logweight
            ]
            for i in eachindex(state.particles)
        ]
    )
    push!(logger.history, history_frame)
    logger
end

function log!(logger::JSONLogger, abs::Abstraction)::Int
    get!(logger.idx_of_abs, abs.expr) do
        logged_abs = [
            string(abs.expr), # expr
            length(abs.matches), # num_matches
            abs.size, # size
            abs.logposterior # logposterior
        ]
        push!(logger.logged_abstractions, logged_abs)
        length(logger.logged_abstractions)
    end
end

log!(logger::JSONLogger, expr::PExpr) = string(expr)

# function log!(logger::JSONLogger, expr::Prim)
#     return string(expr) # prim
# end

# function log!(logger::JSONLogger, expr::MetaVar)
#     return string(expr) # metavar
# end

# function log!(logger::JSONLogger, expr::App)
#     res = []
#     push!(res, log!(logger, expr.f))
#     for arg in expr.args
#         push!(res, log!(logger, arg))
#     end
#     res
# end

function JSON.lower(config::Config)
    res = Dict()
    for field in fieldnames(Config)
        field in [:utility_fn] && continue
        res[field] = getfield(config, field)
    end
    res
end


function JSON.lower(result::SMCResult)
    return Dict(
        :abstraction => log!(result.logger, result.abstraction),
        :before => result.before,
        :rewritten => result.rewritten,
        :stats => result.stats,
        :logger => result.logger
    )
end

function JSON.lower(result::StitchResult)
    return Dict(
        :before => result.before,
        :rewritten => result.rewritten,
        :rounds => result.rounds,
        :stats => result.stats
    )
end

function JSON.lower(e::PExpr)
    return string(e)
end

function JSON.lower(corpus::Corpus)
    return Dict(
        :programs => corpus.programs
    )
end

function JSON.lower(program::Program)
    return string(program.expr)
end

function JSON.lower(n::CorpusNode)
    return string(n.expr)
end


