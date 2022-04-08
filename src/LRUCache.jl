module LRUCache

include("cyclicorderedset.jl")
export LRU

using Base.Iterators
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
    by::Any
    finalizer::Any

    function LRU{K, V}(; maxsize::Int, by = _constone, finalizer = nothing) where {K, V}
        dict = Dict{K, V}()
        keyset = CyclicOrderedSet{K}()
        new{K, V}(dict, keyset , 0, maxsize, SpinLock(), by, finalizer)
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
            return v
        else
            return default
        end
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
    end
    return default()
end
function Base.get!(lru::LRU{K, V}, key, default) where {K, V}
    evictions = Tuple{K, V}[]
    v = lock(lru.lock) do
        if _unsafe_haskey(lru, key)
            v = _unsafe_getindex(lru, key)
            return v
        end
        v = default
        _unsafe_addindex!(lru, v, key)
        _unsafe_resize!(lru, evictions)
        return v
    end
    _finalize_evictions!(lru.finalizer, evictions)
    return v
end
function Base.get!(default::Callable, lru::LRU{K, V}, key) where {K, V}
    evictions = Tuple{K, V}[]
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        v = _unsafe_getindex(lru, key)
        unlock(lru.lock)
        return v
    else
        unlock(lru.lock)
    end
    v = default()
    lock(lru.lock)
    if _unsafe_haskey(lru, key)
        # should we test that this yields the same result as default()
        v = _unsafe_getindex(lru, key)
    else
        _unsafe_addindex!(lru, v, key)
        _unsafe_resize!(lru, evictions)
    end
    unlock(lru.lock)
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
    n = LinkedNode{K}(key)
    rotate!(_push!(lru.keyset, n))
    s = lru.by(v)::Int
    lru.currentsize += s
    lru.dict[key] = (v, n, s)
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
            lru.currentsize += s
            lru.dict[key] = (v, n, s)
            _move_to_front!(lru.keyset, n)
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

# Reverse iterator for LRUCache.LRU
Base.eltype(::Type{Iterators.Reverse{LRUCache.LRU{T}}}) where {T} = eltype(T)
Base.IteratorSize(::Type{Iterators.Reverse{LRUCache.LRU{T}}}) where {T} = Base.IteratorSize(LRUCache.CyclicOrderedSet)
Base.IteratorEltype(::Type{Iterators.Reverse{LRUCache.LRU{T}}}) where {T} = Base.IteratorEltype(LRUCache.LRU)
Base.length(lru::Iterators.Reverse{LRUCache.LRU{T}}) where {T} = length(lru.itr.keyset)
Base.isempty(lru::Iterators.Reverse{LRUCache.LRU{T}}) where {T} = isempty(lru.itr.keyset)

function Base.iterate(lru::Iterators.Reverse{LRU{T,B}}, state...) where {T,B}
    next = iterate(Iterators.Reverse(lru.itr.keyset), state...)
    if next === nothing
        return nothing
    else
        k, state = next
        v, = lru.itr.dict[k]
        return k=>v, state
    end
end

end # module
