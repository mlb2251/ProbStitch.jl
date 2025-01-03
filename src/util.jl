"""
adapted from StatsBase.sample();
this verison requires normalized weights (uncomment the first line sum to work with unnormalized weights)
"""
function sample_normalized(weights)
    t = rand() # * sum(w -> w, weights) 
    n = length(weights)
    i = 1
    @inbounds cw = weights[1]
    while cw < t && i < n
        i += 1
        @inbounds cw += weights[i]
    end
    return i
end

"""
A faster sampler for sampling N independent samples from an unnormalized categorical distribution.
"""
function sample_many!(weights, out)
    N = length(out)
    weights = weights ./ sum(weights)
    rands = sort!(rand(N))
    W = length(weights)

    weights_idx = 1
    @inbounds cumulative_weight = weights[1]

    for j in 1:N
        while (@inbounds cumulative_weight < rands[j] && weights_idx < W)
            @inbounds cumulative_weight += weights[weights_idx]
            weights_idx += 1
        end
        @inbounds out[j] = weights_idx
    end
    out
end
function resample_multinomial!(logweights::Vector{Float64}, out::Vector{Int})
    @assert length(out) == length(logweights)
    total = logsumexp(logweights)
    total == -Inf && return collect(1:length(out))
    weights = exp.(logweights .- total)
    return sample_many!(weights, out)
end

function resample_residual!(logweights::Vector{Float64}, out::Vector{Int})
    @assert length(out) == length(logweights)
    N = length(logweights)
    total = logsumexp(logweights)
    total == -Inf && return collect(1:N)
    Nweights = exp.(logweights .- total) .* N
    whole_weights = floor.(Int, Nweights)
    residual_weights = Nweights .- whole_weights
    residual_weights ./= sum(residual_weights)
    res_idx = 1
    for (i, count) in enumerate(whole_weights)
        for _ in 1:count
            @inbounds out[res_idx] = i
            res_idx += 1
        end
    end
    sample_many!(residual_weights, view(out, res_idx:N))
    out
end


const Id = Int

struct IdSet{T}
    id_of_entry::Dict{T, Id}
    entry_of_id::Vector{T}
end
IdSet{T}() where T = IdSet(Dict{T, Id}(), Vector{T}())
function Base.getindex(idset::IdSet{T}, entry::T) where T
    get!(idset.id_of_entry, entry) do
        push!(idset.entry_of_id, entry)
        length(idset.entry_of_id)
    end
end
function Base.getindex(idset::IdSet{T}, id::Id) where T
    idset.entry_of_id[id]
end

mutable struct HitRate
    hits::Int
    misses::Int
end
HitRate() = HitRate(0, 0)

(Base.:+)(a::HitRate, b::HitRate) = HitRate(a.hits + b.hits, a.misses + b.misses)
Base.show(io::IO, rate::HitRate) = print(io, round(hit_rate(rate) * 100, digits=2), "% (N=", rate.hits + rate.misses, ")")

hit!(rate::HitRate, b::Bool) = b ? hit!(rate) : miss!(rate)
hit!(rate::HitRate) = (rate.hits += 1)
miss!(rate::HitRate) = (rate.misses += 1)
unhit!(rate::HitRate) = (rate.hits -= 1)
unmiss!(rate::HitRate) = (rate.misses -= 1)
hit_rate(rate::HitRate) = rate.hits / (rate.hits + rate.misses)


function logaddexp(x::Float64, y::Float64)::Float64
    if x == -Inf
        return y
    elseif y == -Inf
        return x
    else
        # Numerically stable implementation
        res = max(x, y) + log1p(exp(-abs(x - y)))
        return (res > 0.0 && isapprox(res, 0.0; atol = eps(1.0))) ? 0.0 : res
    end
end

logsumexp(x::Vector{Float64}) = reduce(logaddexp, x; init = -Inf)
