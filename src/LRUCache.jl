module LRUCache

include("cyclicorderedset.jl")
export LRU, cache_info

using Base.Threads
using Base: Callable

_constone(x) = 1

# Default cache size
mutable struct LRU{K,V} <: AbstractDict{K,V}
    dict::Dict{K, Tuple{V, LinkedNode{K}, Int}}
    keyset::CyclicOrderedSet{K}
    currentsize::Int
    maxsize::Int
    hits::Int
    misses::Int
    lock::SpinLock
    by::Any
    finalizer::Any

    function LRU{K, V}(; maxsize::Int, by = _constone, finalizer = nothing) where {K, V}
        dict = Dict{K, V}()
        keyset = CyclicOrderedSet{K}()
        new{K, V}(dict, keyset , 0, maxsize, 0, 0, SpinLock(), by, finalizer)
    end
end

Base.@kwdef struct CacheInfo
    hits::Int
    misses::Int
    currentsize::Int
    maxsize::Int
end

function Base.show(io::IO, c::CacheInfo)
    return print(io, "CacheInfo(; hits=$(c.hits), misses=$(c.misses), currentsize=$(c.currentsize), maxsize=$(c.maxsize))")
end

"""
    cache_info(lru::LRU) -> CacheInfo

Returns a `CacheInfo` object holding a snapshot of information about the cache hits, misses, current size, and maximum size, current as of when the function was called. To access the values programmatically, use property access, e.g. `info.hits`.

Note that only `get!` and `get` contribute to hits and misses, and `empty!` resets the counts of hits and misses to 0.

## Example

```jldoctest
lru = LRU{Int, Float64}(maxsize=10)

get!(lru, 1, 1.0) # miss

get!(lru, 1, 1.0) # hit

get(lru, 2, 2) # miss

get(lru, 2, 2) # miss

info = cache_info(lru)

# output

CacheInfo(; hits=1, misses=3, currentsize=1, maxsize=10)
```
"""
function cache_info(lru::LRU)
    lock(lru.lock) do
        return CacheInfo(; hits=lru.hits, misses=lru.misses, currentsize=lru.currentsize, maxsize=lru.maxsize)
    end
end

LRU(; maxsize::Int, by = _constone, finalizer = nothing) =
    LRU{Any,Any}(maxsize = maxsize, by = by, finalizer = finalizer)

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
function Base.iterate(lru::Iterators.Reverse{<:LRU}, state...)
    next = iterate(Iterators.Reverse(lru.itr.keyset), state...)
    if next === nothing
        return nothing
    else
        k, state = next
        v, = lru.itr.dict[k]
        return k=>v, state
    end
end

Base.length(lru::LRU) = length(lru.keyset)
Base.isempty(lru::LRU) = isempty(lru.keyset)
function Base.sizehint!(lru::LRU, n::Integer)
    lock(lru.lock) do
        sizehint!(lru.dict, n)
    end
    return lru
end

_unsafe_haskey(lru::LRU, key) = haskey(lru.dict, key)
function Base.haskey(lru::LRU, key)
    lock(lru.lock) do
        return _unsafe_haskey(lru, key)
    end
end
function Base.get(lru::LRU, key, default)
    lock(lru.lock) do
        if _unsafe_haskey(lru, key)
            v = _unsafe_getindex(lru, key)
            lru.hits += 1
            return v
        else
            lru.misses += 1
            return default
        end
    end
end
function Base.get(default::Callable, lru::LRU, key)
    lock(lru.lock)
    try
        if _unsafe_haskey(lru, key)
            lru.hits += 1
            return _unsafe_getindex(lru, key)
        end
        lru.misses += 1
    finally
        unlock(lru.lock)
    end
    return default()
end
function Base.get!(lru::LRU{K, V}, key, default) where {K, V}
    evictions = Tuple{K, V}[]
    v = lock(lru.lock) do
        if _unsafe_haskey(lru, key)
            lru.hits += 1
            v = _unsafe_getindex(lru, key)
            return v
        end
        v = default
        _unsafe_addindex!(lru, v, key)
        _unsafe_resize!(lru, evictions)
        lru.misses += 1
        return v
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return v
end
function Base.get!(default::Callable, lru::LRU{K, V}, key) where {K, V}
    evictions = Tuple{K, V}[]
    lock(lru.lock)
    try
        if _unsafe_haskey(lru, key)
            lru.hits += 1
            return _unsafe_getindex(lru, key)
        end
    finally
        unlock(lru.lock)
    end
    v = default()
    lock(lru.lock)
    try
        if _unsafe_haskey(lru, key)
            lru.hits += 1
            # should we test that this yields the same result as default()
            v = _unsafe_getindex(lru, key)
        else
            _unsafe_addindex!(lru, v, key)
            _unsafe_resize!(lru, evictions)
            lru.misses += 1
        end
    finally
        unlock(lru.lock)
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return v
end

function _unsafe_getindex(lru::LRU, key)
    v, n, s = lru.dict[key]
    _move_to_front!(lru.keyset, n)
    return v
end
function Base.getindex(lru::LRU, key)
    lock(lru.lock) do
        if _unsafe_haskey(lru, key)
            v = _unsafe_getindex(lru, key)
            return v
        else
            throw(KeyError(key))
        end
    end
end
function _unsafe_addindex!(lru::LRU{K}, v, key) where K
    s = lru.by(v)::Int
    # If entry is larger than entire cache, don't add it
    s > lru.maxsize && return
    n = LinkedNode{K}(key)
    rotate!(_push!(lru.keyset, n))
    lru.currentsize += s
    lru.dict[key] = (v, n, s)
    return
end
function Base.setindex!(lru::LRU{K, V}, v, key) where {K, V}
    evictions = Tuple{K, V}[]
    lock(lru.lock) do
        if _unsafe_haskey(lru, key)
            old_v, n, s = lru.dict[key]
            if lru.finalizer !== nothing
                push!(evictions, (key, old_v))
            end
            lru.currentsize -= s
            s = lru.by(v)::Int
            # If new entry is larger than entire cache, don't add it
            # (but still evict the old entry!)
            if s > lru.maxsize
                # We are inside the lock still, so we will remove it manually rather than
                # `delete!(lru, key)` which would need the lock again.
                delete!(lru.dict, key)
                _delete!(lru.keyset, n)
            else # add the new entry
                lru.currentsize += s
                lru.dict[key] = (v, n, s)
                _move_to_front!(lru.keyset, n)
            end
        else
            _unsafe_addindex!(lru, v, key)
        end
        _unsafe_resize!(lru, evictions)
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return lru
end

function _unsafe_resize!(lru::LRU{K, V}, evictions::Vector{Tuple{K, V}},
                         maxsize::Integer = lru.maxsize) where {K, V}
    lru.maxsize = maxsize
    while lru.currentsize > lru.maxsize
        key = pop!(lru.keyset)
        v, n, s = pop!(lru.dict, key)
        if lru.finalizer !== nothing
            push!(evictions, (key, v))
        end
        lru.currentsize -= s
    end
    return
end
function Base.resize!(lru::LRU{K, V}; maxsize::Integer = lru.maxsize) where {K, V}
    @assert 0 <= maxsize
    evictions = Tuple{K, V}[]
    lock(lru.lock) do
        _unsafe_resize!(lru, evictions, maxsize)
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return lru
end

function Base.delete!(lru::LRU{K, V}, key) where {K, V}
    v = lock(lru.lock) do
        v, n, s = pop!(lru.dict, key)
        lru.currentsize -= s
        _delete!(lru.keyset, n)
        return v
    end
    if lru.finalizer !== nothing
        lru.finalizer(key, v)
    end
    return lru
end
function Base.pop!(lru::LRU{K, V}, key) where {K, V}
    (key, v) = lock(lru.lock) do
        v, n, s = pop!(lru.dict, key)
        lru.currentsize -= s
        _delete!(lru.keyset, n)
        return (key, v)
    end
    if lru.finalizer !== nothing
        lru.finalizer(key, v)
    end
    return v
end

function Base.empty!(lru::LRU{K, V}) where {K, V}
    evictions = Tuple{K, V}[]
    lock(lru.lock) do
        if lru.finalizer === nothing
            lru.currentsize = 0
            empty!(lru.dict)
            empty!(lru.keyset)
        else
            sizehint!(evictions, length(lru))
            _unsafe_resize!(lru, evictions, 0)
        end
        lru.hits = 0
        lru.misses = 0
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return lru
end

function _finalize_evictions!(finalizer, evictions)
    for (key, value) in evictions
        finalizer(key, value)
    end
    return
end

end # module
