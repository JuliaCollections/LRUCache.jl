module LRUCache

export LRU, @get!

include("list.jl")

# Default cache size
const __MAXCACHE__ = 100

mutable struct LRU{K,V} <: AbstractDict{K,V}
    ht::Dict{K, LRUNode{K, V}}
    q::LRUList{K, V}
    maxsize::Int

    LRU{K, V}(m::Int=__MAXCACHE__) where {K, V} = new{K, V}(Dict{K, V}(), LRUList{K, V}(), m)
end
LRU(m::Int=__MAXCACHE__) = LRU{Any, Any}(m)

Base.show(io::IO, lru::LRU{K, V}) where {K, V} = print(io,"LRU{$K, $V}($(lru.maxsize))")

Base.iterate(lru::LRU) = iterate(lru.ht)
Base.iterate(lru::LRU, state) = iterate(lru.ht, state)

Base.length(lru::LRU) = length(lru.q)
Base.isempty(lru::LRU) = isempty(lru.q)
Base.sizehint!(lru::LRU, n::Integer) = sizehint!(lru.ht, n)

Base.haskey(lru::LRU, key) = haskey(lru.ht, key)
Base.get(lru::LRU, key, default) = haskey(lru, key) ? lru[key] : default

macro get!(lru, key, default)
    quote
        if haskey($(esc(lru)), $(esc(key)))
            value = $(esc(lru))[$(esc(key))]
        else
            value = $(esc(default))
            $(esc(lru))[$(esc(key))] = value
        end
        value
    end
end

function Base.get!(default::Base.Callable, lru::LRU{K, V}, key::K) where {K,V}
    if haskey(lru, key)
        return lru[key]
    else
        value = default()
        lru[key] = value
        return value
    end
end

function Base.get!(lru::LRU{K,V}, key::K, default::V) where {K,V}
    if haskey(lru, key)
        return lru[key]
    else
        lru[key] = default
        return default
    end
end

function Base.getindex(lru::LRU, key)
    node = lru.ht[key]
    move_to_front!(lru.q, node)
    return node.v
end

function Base.setindex!(lru::LRU{K, V}, v, key) where {K, V}
    if haskey(lru, key)
        item = lru.ht[key]
        item.v = v
        move_to_front!(lru.q, item)
    elseif length(lru) == lru.maxsize
        # At capacity. Roll the list so last el is now first, remove the old
        # data, and update new data in place.
        rotate!(lru.q)
        item = first(lru.q)
        delete!(lru.ht, item.k)
        item.k = key
        item.v = v
        lru.ht[key] = item
    else
        item = LRUNode{K, V}(key, v)
        pushfirst!(lru.q, item)
        lru.ht[key] = item
    end
    return lru
end

function Base.resize!(lru::LRU, n::Int)
    n < 0 && error("size must be a positive integer")
    lru.maxsize = n
    for i in 1:(length(lru) - lru.maxsize)
        rm = pop!(lru.q)
        delete!(lru.ht, rm.k)
    end
    return lru
end

function Base.delete!(lru::LRU, key)
    item = lru.ht[key]
    delete!(lru.q, item)
    delete!(lru.ht, key)
    return lru
end

function Base.empty!(lru::LRU)
    empty!(lru.ht)
    empty!(lru.q)
end

end # module
