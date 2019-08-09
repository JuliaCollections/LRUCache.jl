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
    lock(lru.lock)
    sizehint!(lru.dict, n)
    unlock(lru.lock)
    return lru
end

_unsafe_haskey(lru::LRU, key) = haskey(lru.dict, key)
function Base.haskey(lru::LRU, key)
    lock(lru.lock)
    b = _unsafe_haskey(lru, key)
    unlock(lru.lock)
    return b
end
function Base.get(lru::LRU, key, default)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    else
        unlock(lru.lock)
        return default
    end
end
function Base.get(default::Callable, lru::LRU, key)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    else
        unlock(lru.lock)
        return default()
    end
end
function Base.get!(lru::LRU, key, default)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    end
    v = default
    _unsafe_addindex!(lru, v, key)
    _unsafe_resize!(lru)
    unlock(lru.lock)
    return v
end
function Base.get!(default::Callable, lru::LRU, key)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    end
    v = default()
    _unsafe_addindex!(lru, v, key)
    _unsafe_resize!(lru)
    unlock(lru.lock)
    return v
end

function _unsafe_getindex(lru::LRU, key)
    v, n, s = lru.dict[key]
    _move_to_front!(lru.keyset, n)
    return v
end
function Base.getindex(lru::LRU, key)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    else
        unlock(lru.lock)
        throw(KeyError(key))
    end
end
function _unsafe_addindex!(lru::LRU{K}, v, key) where K
    n = LinkedNode{K}(key)
    rotate!(_push!(lru.keyset, n))
    s = lru.by(v)::Int
    lru.currentsize += s
    lru.dict[key] = (v, n, s)
end
function Base.setindex!(lru::LRU, v, key)
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        _, n, s = lru.dict[key]
        lru.currentsize -= s
        s = lru.by(v)::Int
        lru.currentsize += s
        lru.dict[key] = (v, n, s)
        _move_to_front!(lru.keyset, n)
    else
        _unsafe_addindex!(lru, v, key)
    end
    _unsafe_resize!(lru)
    unlock(lru.lock)
    return lru
end

function _unsafe_resize!(lru::LRU, maxsize::Integer = lru.maxsize)
    lru.maxsize = maxsize
    while lru.currentsize > lru.maxsize
        key = pop!(lru.keyset)
        v, n, s = pop!(lru.dict, key)
        lru.currentsize -= s
    end
    return lru
end
function Base.resize!(lru::LRU; maxsize::Integer = lru.maxsize)
    @assert 0 <= maxsize
    lock(lru.lock)
    _unsafe_resize!(lru, maxsize)
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
