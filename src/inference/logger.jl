

const PARTICLE_FIELDNAMES = ["abs_id", "logweight"]
const ABS_FIELDNAMES = ["expr", "num_matches", "size", "utility"]

mutable struct JSONLogger
    state::SMC
    config::Config
    shared::Shared
    history::Vector{Any}
    idx_of_abs::Dict{PExpr, Int}
    logged_abstractions::Vector{Any}
end

function JSON.lower(logger::JSONLogger)
    return Dict(
        :config => logger.config,
        :history => logger.history,
        :logged_abstractions => logger.logged_abstractions,
    )
end


function JSONLogger(smc::SMC, config::Config, shared::Shared)
    return JSONLogger(smc, config, shared, [], Dict{PExpr, Int}(), [])
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
            log!(logger, abs.expr), # expr
            length(abs.matches), # num_matches
            abs.size, # size
            abs.utility # utility
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
        :steps => result.steps,
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


