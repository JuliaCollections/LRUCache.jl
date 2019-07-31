module LRUCache

include("cyclicorderedset.jl")
export LRU

using Base.Threads
using Base: Callable

_constone(x) = 1

# Default cache size
mutable struct LRU{K,V} <: AbstractDict{K,V}
    dict::Dict{K, Tuple{V, LinkedNode{K}, Int}}
    keyset::CyclicOrderedSet{K}
    currentsize::Int
    maxsize::Int
    lock::SpinLock
    by::Callable

    LRU{K, V}(; maxsize::Int, by::Callable = _constone) where {K, V} =
        new{K, V}(Dict{K, V}(), CyclicOrderedSet{K}(), 0, maxsize, SpinLock(), by)
end

Base.show(io::IO, lru::LRU{K, V}) where {K, V} =
    print(io, "LRU{$K, $V}(; maxsize = $(lru.maxsize))")

function Base.iterate(lru::LRU, state...)
    next = iterate(lru.keyset, state...)
    if next === nothing
        return nothing
    else
        k, state = next
        v, = lru.dict[k]
        return k=>v, state
    end
end

Base.length(lru::LRU) = length(lru.keyset)
Base.isempty(lru::LRU) = isempty(lru.keyset)
function Base.sizehint!(lru::LRU, n::Integer)
    sizehint!(lru.dict, n)
    return lru
end

Base.haskey(lru::LRU, key) = haskey(lru.dict, key)
Base.get(lru::LRU, key, default) = haskey(lru, key) ? lru[key] : default
Base.get(default::Callable, lru::LRU, key) = haskey(lru, key) ? lru[key] : default()

Base.get!(default::Callable, lru::LRU, key) =
    haskey(lru, key) ? lru[key] : (lru[key] = default())
Base.get!(lru::LRU, key, default) = haskey(lru, key) ? lru[key] : (lru[key] = default)

function Base.getindex(lru::LRU, key)
    lock(lru.lock)
    v, n, s = lru.dict[key]
    _move_to_front!(lru.keyset, n)
    unlock(lru.lock)
    return v
end
function Base.setindex!(lru::LRU{K, V}, v, key) where {K, V}
    lock(lru.lock)
    if haskey(lru, key)
        _, n, s = lru.dict[key]
        lru.currentsize -= s
        s = lru.by(v)::Int
        lru.currentsize += s
        lru.dict[key] = (v, n, s)
        _move_to_front!(lru.keyset, n)
    else
        n = LinkedNode{K}(key)
        rotate!(_push!(lru.keyset, n))
        s = lru.by(v)::Int
        lru.currentsize += s
        lru.dict[key] = (v, n, s)
    end
    while lru.currentsize > lru.maxsize
        k = pop!(lru.keyset)
        _, _, s = pop!(lru.dict, k)
        lru.currentsize -= s
    end
    unlock(lru.lock)
    return lru
end

function Base.resize!(lru::LRU; maxsize::Integer = 0)
    @assert 0 <= maxsize
    lock(lru.lock)
    lru.maxsize = maxsize
    while lru.currentsize > lru.maxsize
        key = pop!(lru.keyset)
        v, n, s = pop!(lru.dict, key)
        lru.currentsize -= s
    end
    unlock(lru.lock)
    return lru
end

function Base.delete!(lru::LRU, key)
    lock(lru.lock)
    v, n, s = pop!(lru.dict, key)
    lru.currentsize -= s
    _delete!(lru.keyset, n)
    unlock(lru.lock)
    return lru
end
function Base.pop!(lru::LRU, key)
    lock(lru.lock)
    v, n, s = pop!(lru.dict, key)
    lru.currentsize -= s
    _delete!(lru.keyset, n)
    unlock(lru.lock)
    return v
end

function Base.empty!(lru::LRU)
    lock(lru.lock)
    lru.currentsize = 0
    empty!(lru.dict)
    empty!(lru.keyset)
    unlock(lru.lock)
    return lru
end

end # module
